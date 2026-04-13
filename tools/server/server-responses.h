#pragma once

#include "server-common.h"

#include <cstdint>
#include <list>
#include <mutex>
#include <string>
#include <unordered_map>

struct server_responses_slot_binding {
    int id_slot = -1;
    uint64_t slot_epoch = 0;
};

struct server_responses_request_context {
    std::string parent_response_id;
    std::string resolved_instructions;
    json input_items = json::array();
};

struct server_responses_request_resolution {
    json body;
    server_responses_request_context context;
    server_responses_slot_binding preferred_slot_binding;
};

class server_responses_history {
public:
    explicit server_responses_history(size_t max_entries = 128);

    server_responses_request_resolution resolve_request(const json & request);

    void remember_response(
        const server_responses_request_context & request_context,
        const json & response,
        server_responses_slot_binding slot_binding);

private:
    struct node {
        std::string response_id;
        std::string parent_response_id;
        std::string resolved_instructions;
        json input_items = json::array();
        json output_items = json::array();
        server_responses_slot_binding slot_binding;
    };

    struct entry {
        node value;
        std::list<std::string>::iterator lru_it;
    };

    json normalize_input_items(const json & input) const;
    json flatten_items_locked(const std::string & response_id) const;
    entry & get_entry_locked(const std::string & response_id);
    void touch_locked(entry & value);
    void evict_locked();

    const size_t max_entries;
    mutable std::mutex mutex;
    std::list<std::string> lru;
    std::unordered_map<std::string, entry> entries;
};
