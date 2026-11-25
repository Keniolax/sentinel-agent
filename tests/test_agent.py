import json
import threading
from http.server import ThreadingHTTPServer

import pytest

from sentinel import agent, orders_api
from sentinel.tools import Tools


class FakeStore:
    """Stands in for blob.BlobStore and records every call that would reach storage."""

    def __init__(self, objects):
        self.objects, self.calls = objects, []

    def list(self, prefix, limit):
        self.calls.append(("list", prefix, limit))
        return [k for k in self.objects if k.startswith(prefix)][:limit]

    def get(self, key, max_bytes):
        self.calls.append(("get", key, max_bytes))
        return self.objects[key].encode()[:max_bytes]


class ScriptedModel:
    """Returns the replies it was given, one per request, and records each request."""
    name = "scripted"

    def __init__(self, *replies):
        self.replies, self.requests = list(replies), []

    def chat(self, messages, tools):
        self.requests.append([dict(m) for m in messages])
        return self.replies.pop(0)


def call(name, **arguments):
    return {"content": "", "tool_calls": [{"function": {"name": name, "arguments": arguments}}]}


def answer(text):
    return {"content": text}


@pytest.fixture
def orders_url():
    server = ThreadingHTTPServer(("127.0.0.1", 0), orders_api.Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{server.server_port}"
    server.shutdown()


@pytest.fixture
def store():
    return FakeStore({"kb/returns.md": "Returns within 30 days.", "kb/shipping.md": "Ships in 2 days."})


def events(capsys):
    return [json.loads(line) for line in capsys.readouterr().out.splitlines() if line.startswith("{")]


def test_allowed_read_reaches_storage_and_the_model(capsys, store, orders_url):
    model = ScriptedModel(call("kb_get", key="kb/returns.md"), answer("30 days."))
    assert agent.ask("Return window?", model, Tools(store, "kb", orders_url), run_id="r1") == "30 days."
    assert store.calls == [("get", "kb/returns.md", 8000)]
    assert model.requests[1][-1] == {"role": "tool", "content": "Returns within 30 days.", "tool_name": "kb_get"}
    tool = [e for e in events(capsys) if e["event"] == "tool_call"][0]
    assert (tool["decision"], tool["key"], tool["container"], tool["run_id"]) == ("allowed", "kb/returns.md", "kb", "r1")


@pytest.mark.parametrize("key", [
    "finance/payroll-2026-11.csv", "kb/../finance/payroll-2026-11.csv", "kb/a/../../finance/x",
    "/kb/returns.md", "kb/", "https://other.blob.core.windows.net/kb/returns.md", "KB/returns.md", "kb//returns.md", 7,
])
def test_key_outside_the_knowledge_base_is_denied_before_storage(capsys, store, orders_url, key):
    model = ScriptedModel(call("kb_get", key=key), answer("done"))
    agent.ask("q", model, Tools(store, "kb", orders_url))
    assert store.calls == []
    tool = [e for e in events(capsys) if e["event"] == "tool_call"][0]
    assert tool["decision"] == "denied"
    assert "error" in json.loads(model.requests[1][-1]["content"])


@pytest.mark.parametrize("name, arguments", [
    ("blob_get", {"container": "finance", "key": "records/payroll.csv"}),
    ("kb_get", {"key": "kb/returns.md", "container": "finance"}),
    ("kb_list", {"prefix": "finance/"}),
    ("orders_lookup", {"order_id": "LK-55120/../admin"}),
])
def test_unknown_tool_or_extra_argument_is_denied(capsys, store, orders_url, name, arguments):
    model = ScriptedModel(call(name, **arguments), answer("done"))
    agent.ask("q", model, Tools(store, "kb", orders_url))
    assert store.calls == []
    assert [e["decision"] for e in events(capsys) if e["event"] == "tool_call"] == ["denied"]


def test_list_stays_on_the_knowledge_base_prefix(capsys, orders_url):
    store = FakeStore({"kb/returns.md": "x", "records/payroll.csv": "y"})
    model = ScriptedModel(call("kb_list"), answer("done"))
    agent.ask("q", model, Tools(store, "kb", orders_url))
    assert store.calls == [("list", "kb/", 50)]
    assert json.loads(model.requests[1][-1]["content"]) == ["kb/returns.md"]


def test_order_lookup_calls_the_internal_api(capsys, store, orders_url):
    model = ScriptedModel(call("orders_lookup", order_id="LK-55120"), answer("Shipped."))
    agent.ask("Where is LK-55120?", model, Tools(store, "kb", orders_url))
    assert json.loads(model.requests[1][-1]["content"])["status"] == "shipped"
    tool = [e for e in events(capsys) if e["event"] == "tool_call"][0]
    assert (tool["decision"], tool["http_status"]) == ("allowed", 200)


def test_a_failing_tool_gives_the_model_no_detail(capsys, orders_url):
    class Broken(FakeStore):
        def get(self, key, max_bytes):
            raise RuntimeError("AuthorizationPermissionMismatch for principal 00000000-0000-0000-0000-000000000000")

    model = ScriptedModel(call("kb_get", key="kb/returns.md"), answer("done"))
    agent.ask("q", model, Tools(Broken({}), "kb", orders_url))
    assert json.loads(model.requests[1][-1]["content"]) == {"error": "the tool failed"}
    tool = [e for e in events(capsys) if e["event"] == "tool_call"][0]
    assert (tool["decision"], tool["reason"]) == ("error", "RuntimeError")


def test_the_loop_stops_after_four_steps(capsys, store, orders_url):
    model = ScriptedModel(*[call("kb_list")] * 4)
    assert agent.ask("q", model, Tools(store, "kb", orders_url)) == "I could not finish that request."
    assert len(model.requests) == 4
    assert events(capsys)[-1]["stopped"] == "max_steps"


def test_logs_hold_hashes_not_the_question_or_answer(capsys, store, orders_url):
    model = ScriptedModel(answer("secret answer text"))
    agent.ask("my private question", model, Tools(store, "kb", orders_url))
    out = json.dumps(events(capsys))
    assert "my private question" not in out and "secret answer text" not in out
    assert agent.sha256("my private question") in out
