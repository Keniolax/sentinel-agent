import io
import json

from sentinel import model


def sent_url(monkeypatch, **kw):
    seen = []

    def fake_urlopen(req, timeout):
        seen.append(req.full_url)
        return io.BytesIO(json.dumps({"message": {"content": "ok"}}).encode())

    monkeypatch.setattr(model.urllib.request, "urlopen", fake_urlopen)
    model.Ollama(**kw).chat([{"role": "user", "content": "q"}], [])
    return seen[0]


def test_bare_host_port_from_the_image_gets_a_scheme(monkeypatch):
    # The image sets OLLAMA_HOST=127.0.0.1:11434 for `ollama serve`; the client shares it.
    monkeypatch.setenv("OLLAMA_HOST", "127.0.0.1:11434")
    assert sent_url(monkeypatch) == "http://127.0.0.1:11434/api/chat"


def test_a_full_url_is_kept(monkeypatch):
    assert sent_url(monkeypatch, host="http://localhost:9999/") == "http://localhost:9999/api/chat"
