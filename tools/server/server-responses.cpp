#include "server-responses.h"

#include <stdexcept>
#include <unordered_set>
#include <utility>
#include <vector>

server_responses_history::server_responses_history(size_t max_entries)
    : max_entries(max_entries) {}

json server_responses_history::normalize_input_items(const json & input) const {
    if (input.is_string()) {
        return json::array({
            json {
                {"role", "user"},
                {"content", input},
            },
        });
    }

    if (!input.is_array()) {
        throw std::invalid_argument("'input' must be a string or array of objects");
    }

    for (const json & item : input) {
        if (!item.is_object()) {
            throw std::invalid_argument("'input' array items must be objects");
        }
    }

    return input;
}

server_responses_history::entry & server_responses_history::get_entry_locked(const std::string & response_id) {
    auto it = entries.find(response_id);
    if (it == entries.end()) {
        throw std::invalid_argument("Unknown 'previous_response_id': '" + response_id + "'");
    }

    touch_locked(it->second);
    return it->second;
}

void server_responses_history::touch_locked(entry & value) {
    lru.erase(value.lru_it);
    lru.push_front(value.value.response_id);
    value.lru_it = lru.begin();
}

void server_responses_history::evict_locked() {
    while (entries.size() > max_entries && !lru.empty()) {
        const std::string & response_id = lru.back();
        entries.erase(response_id);
        lru.pop_back();
    }
}

json server_responses_history::flatten_items_locked(const std::string & response_id) const {
    std::vector<const node *> chain;
    std::unordered_set<std::string> visited;
    std::string current = response_id;

    while (!current.empty()) {
        auto it = entries.find(current);
        if (it == entries.end()) {
            throw std::invalid_argument("Unknown 'previous_response_id': '" + response_id + "'");
        }

        if (!visited.insert(current).second) {
            throw std::invalid_argument("Cycle detected while resolving 'previous_response_id'");
        }

        chain.push_back(&it->second.value);
        current = it->second.value.parent_response_id;
    }

    json items = json::array();
    for (auto it = chain.rbegin(); it != chain.rend(); ++it) {
        for (const json & item : (*it)->input_items) {
            items.push_back(item);
        }
        for (const json & item : (*it)->output_items) {
            items.push_back(item);
        }
    }

    return items;
}

server_responses_request_resolution server_responses_history::resolve_request(const json & request) {
    if (!request.contains("input")) {
        throw std::invalid_argument("'input' is required");
    }

    server_responses_request_resolution resolution;
    resolution.body = request;
    resolution.body.erase("previous_response_id");
    resolution.context.parent_response_id = json_value(request, "previous_response_id", std::string());
    resolution.context.input_items = normalize_input_items(request.at("input"));

    std::lock_guard<std::mutex> lock(mutex);

    if (resolution.context.parent_response_id.empty()) {
        resolution.context.resolved_instructions = json_value(request, "instructions", std::string());
        resolution.body["input"] = resolution.context.input_items;
    } else {
        entry & parent = get_entry_locked(resolution.context.parent_response_id);
        json input_items = flatten_items_locked(resolution.context.parent_response_id);
        for (const json & item : resolution.context.input_items) {
            input_items.push_back(item);
        }

        resolution.context.resolved_instructions = request.contains("instructions")
            ? json_value(request, "instructions", std::string())
            : parent.value.resolved_instructions;
        resolution.body["input"] = std::move(input_items);
        resolution.preferred_slot_binding = parent.value.slot_binding;
    }

    if (resolution.context.resolved_instructions.empty()) {
        resolution.body.erase("instructions");
    } else {
        resolution.body["instructions"] = resolution.context.resolved_instructions;
    }

    return resolution;
}

void server_responses_history::remember_response(
    const server_responses_request_context & request_context,
    const json & response,
    server_responses_slot_binding slot_binding) {
    if (!response.is_object() || !response.contains("id") || !response.at("id").is_string()) {
        return;
    }

    if (!response.contains("output") || !response.at("output").is_array()) {
        return;
    }

    node value;
    value.response_id = response.at("id").get<std::string>();
    value.parent_response_id = request_context.parent_response_id;
    value.resolved_instructions = request_context.resolved_instructions;
    value.input_items = request_context.input_items;
    value.output_items = response.at("output");
    value.slot_binding = slot_binding;

    std::lock_guard<std::mutex> lock(mutex);

    auto existing = entries.find(value.response_id);
    if (existing != entries.end()) {
        lru.erase(existing->second.lru_it);
        entries.erase(existing);
    }

    lru.push_front(value.response_id);
    entry stored;
    stored.value = std::move(value);
    stored.lru_it = lru.begin();
    entries.emplace(stored.value.response_id, std::move(stored));

    evict_locked();
}
