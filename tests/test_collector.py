import importlib.util
import json
import pathlib

spec = importlib.util.spec_from_file_location(
    "collector", pathlib.Path(__file__).parent.parent / "siem" / "collector.py")
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


def test_agent_json_line_becomes_a_nested_object():
    row = {"sentinel_source": "job", "line": '{"app": "sentinel-agent", "event": "answer", "run_id": "r1"}',
           "execution": "", "ingested": "t"}
    out = collector.shape(row)
    assert out["sentinel"] == {"app": "sentinel-agent", "event": "answer", "run_id": "r1"}
    assert "line" not in out and "execution" not in out


def test_plain_text_line_is_kept_as_text():
    out = collector.shape({"sentinel_source": "job", "line": "{not json"})
    assert out["line"] == "{not json" and "sentinel" not in out


def test_checkpoint_moves_to_the_last_ingested_row(tmp_path, monkeypatch):
    out, state = tmp_path / "azure.json", tmp_path / "state" / "checkpoint"
    state.parent.mkdir()
    state.write_text("2026-11-25T00:00:00Z")
    seen = []
    rows = [{"sentinel_source": "storage", "OperationName": "GetBlob", "ingested": "2026-11-25T00:01:00Z"},
            {"sentinel_source": "storage", "OperationName": "ListBlobs", "ingested": "2026-11-25T00:02:00Z"}]
    monkeypatch.setattr(collector, "OUT", str(out))
    monkeypatch.setattr(collector, "STATE", str(state))
    monkeypatch.setattr(collector, "query", lambda since: seen.append(since) or rows)
    collector.main()
    assert seen == ["2026-11-25T00:00:00Z"]
    assert [json.loads(line)["OperationName"] for line in out.read_text().splitlines()] == ["GetBlob", "ListBlobs"]
    assert state.read_text() == "2026-11-25T00:02:00Z"


def test_no_rows_leaves_the_checkpoint(tmp_path, monkeypatch):
    out, state = tmp_path / "azure.json", tmp_path / "checkpoint"
    state.write_text("2026-11-25T00:00:00Z")
    monkeypatch.setattr(collector, "OUT", str(out))
    monkeypatch.setattr(collector, "STATE", str(state))
    monkeypatch.setattr(collector, "query", lambda since: [])
    collector.main()
    assert state.read_text() == "2026-11-25T00:00:00Z"
