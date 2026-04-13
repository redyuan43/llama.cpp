import pytest
from openai import OpenAI
from utils import *

server: ServerProcess

@pytest.fixture(autouse=True)
def create_server():
    global server
    server = ServerPreset.tinyllama2()

def test_responses_with_openai_library():
    global server
    server.start()
    client = OpenAI(api_key="dummy", base_url=f"http://{server.server_host}:{server.server_port}/v1")
    res = client.responses.create(
        model="gpt-4.1",
        input=[
            {"role": "system", "content": "Book"},
            {"role": "user", "content": "What is the best book"},
        ],
        max_output_tokens=8,
        temperature=0.8,
    )
    assert res.id.startswith("resp_")
    assert res.output[0].id is not None
    assert res.output[0].id.startswith("msg_")
    assert match_regex("(Suddenly)+", res.output_text)

def test_responses_stream_with_openai_library():
    global server
    server.start()
    client = OpenAI(api_key="dummy", base_url=f"http://{server.server_host}:{server.server_port}/v1")
    stream = client.responses.create(
        model="gpt-4.1",
        input=[
            {"role": "system", "content": "Book"},
            {"role": "user", "content": "What is the best book"},
        ],
        max_output_tokens=8,
        temperature=0.8,
        stream=True,
    )

    gathered_text = ''
    resp_id = ''
    msg_id = ''
    for r in stream:
        if r.type == "response.created":
            assert r.response.id.startswith("resp_")
            resp_id = r.response.id
        if r.type == "response.in_progress":
            assert r.response.id == resp_id
        if r.type == "response.output_item.added":
            assert r.item.id is not None
            assert r.item.id.startswith("msg_")
            msg_id = r.item.id
        if (r.type == "response.content_part.added" or
            r.type == "response.output_text.delta" or
            r.type == "response.output_text.done" or
            r.type == "response.content_part.done"):
            assert r.item_id == msg_id
        if r.type == "response.output_item.done":
            assert r.item.id == msg_id

        if r.type == "response.output_text.delta":
            gathered_text += r.delta
        if r.type == "response.completed":
            assert r.response.id.startswith("resp_")
            assert r.response.output[0].id is not None
            assert r.response.output[0].id.startswith("msg_")
            assert gathered_text == r.response.output_text
            assert match_regex("(Suddenly)+", r.response.output_text)


def test_responses_previous_response_id_reuses_cached_tokens():
    global server
    server.n_slots = 1
    server.start()

    first = server.make_request("POST", "/v1/responses", data={
        "model": "gpt-4.1",
        "instructions": "Be concise",
        "input": "Say hello in one word",
        "max_output_tokens": 8,
        "temperature": 0.0,
    })

    assert first.status_code == 200
    assert first.body["id"].startswith("resp_")

    second = server.make_request("POST", "/v1/responses", data={
        "model": "gpt-4.1",
        "previous_response_id": first.body["id"],
        "input": "Now say goodbye in one word",
        "max_output_tokens": 8,
        "temperature": 0.0,
    })

    assert second.status_code == 200
    assert second.body["usage"]["input_tokens_details"]["cached_tokens"] > 0


def test_responses_previous_response_id_stream_round_trip():
    global server
    server.n_slots = 1
    server.start()

    response_id = None
    for event in server.make_stream_request("POST", "/v1/responses", data={
        "model": "gpt-4.1",
        "instructions": "Be concise",
        "input": "Say hello in one word",
        "max_output_tokens": 8,
        "temperature": 0.0,
        "stream": True,
    }):
        if event["type"] == "response.completed":
            response_id = event["response"]["id"]

    assert response_id is not None

    second = server.make_request("POST", "/v1/responses", data={
        "model": "gpt-4.1",
        "previous_response_id": response_id,
        "input": "Now say goodbye in one word",
        "max_output_tokens": 8,
        "temperature": 0.0,
    })

    assert second.status_code == 200
    assert second.body["usage"]["input_tokens_details"]["cached_tokens"] > 0


def test_responses_previous_response_id_unknown():
    global server
    server.start()

    res = server.make_request("POST", "/v1/responses", data={
        "model": "gpt-4.1",
        "previous_response_id": "resp_missing",
        "input": "Say hello",
        "max_output_tokens": 8,
        "temperature": 0.0,
    })

    assert res.status_code == 400
    assert "Unknown 'previous_response_id'" in res.body["error"]["message"]
