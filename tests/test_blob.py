from types import SimpleNamespace

from sentinel.blob import BlobStore


class FakeContainerClient:
    """Records the arguments BlobStore sends to the Azure SDK."""

    def __init__(self, names, data=b""):
        self.names, self.data, self.calls = names, data, []

    def list_blobs(self, **kw):
        self.calls.append(("list_blobs", kw))
        return iter(SimpleNamespace(name=n) for n in self.names)

    def download_blob(self, key, **kw):
        self.calls.append(("download_blob", key, kw))
        return SimpleNamespace(readall=lambda: self.data[kw["offset"]:kw["offset"] + kw["length"]])


def test_list_sends_the_prefix_and_stops_at_the_limit():
    client = FakeContainerClient([f"kb/{i}.md" for i in range(80)])
    keys = BlobStore(client).list("kb/", 50)
    assert len(keys) == 50
    assert client.calls == [("list_blobs", {"name_starts_with": "kb/", "results_per_page": 50})]


def test_get_asks_storage_for_a_bounded_range():
    client = FakeContainerClient([], data=b"x" * 20000)
    body = BlobStore(client).get("kb/returns.md", 8000)
    assert len(body) == 8000
    assert client.calls == [("download_blob", "kb/returns.md", {"offset": 0, "length": 8000})]
