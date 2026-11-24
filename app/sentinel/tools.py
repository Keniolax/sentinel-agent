"""The agent's three tools and the checks that run before each one.

The model proposes a tool call. Code decides whether it runs. A call that fails a check is
logged as denied and the model gets a short error, never the data. IAM gives the same limit
a second time: the task role can read only the knowledge-base prefix.
"""

import json
import os
import re
import urllib.error
import urllib.request

KB_PREFIX = "kb/"
KEY_RE = re.compile(r"^kb/[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*$")
ORDER_RE = re.compile(r"^LK-\d{5}$")
MAX_OBJECT_BYTES = 8000
MAX_LIST = 50

TOOL_SPECS = [
    {"type": "function", "function": {
        "name": "kb_list",
        "description": "List the help articles in the knowledge base.",
        "parameters": {"type": "object", "properties": {}, "required": []}}},
    {"type": "function", "function": {
        "name": "kb_get",
        "description": "Read one help article by its key, for example kb/returns.md.",
        "parameters": {"type": "object", "properties": {"key": {"type": "string"}}, "required": ["key"]}}},
    {"type": "function", "function": {
        "name": "orders_lookup",
        "description": "Look up an order's status by order ID, for example LK-55120.",
        "parameters": {"type": "object", "properties": {"order_id": {"type": "string"}}, "required": ["order_id"]}}},
]


class Denied(Exception):
    """A tool call that a check refused. The message is safe to show the model."""


def _args(arguments, allowed):
    if not isinstance(arguments, dict) or not set(arguments) <= set(allowed):
        raise Denied(f"arguments must be an object with only {sorted(allowed)}")
    return arguments


class Tools:
    def __init__(self, s3, bucket, orders_url):
        self.s3 = s3
        self.bucket = bucket
        self.orders_url = orders_url.rstrip("/")

    def run(self, name, arguments):
        """Return (result_text, log_fields). Raise Denied when a check refuses the call."""
        if name == "kb_list":
            _args(arguments, [])
            resp = self.s3.list_objects_v2(Bucket=self.bucket, Prefix=KB_PREFIX, MaxKeys=MAX_LIST)
            keys = [o["Key"] for o in resp.get("Contents", []) if KEY_RE.match(o["Key"])]
            return json.dumps(keys), {"bucket": self.bucket, "prefix": KB_PREFIX, "count": len(keys)}
        if name == "kb_get":
            key = _args(arguments, ["key"]).get("key")
            if not isinstance(key, str) or not KEY_RE.match(key) or ".." in key:
                raise Denied("key must be a knowledge-base key such as kb/returns.md")
            obj = self.s3.get_object(Bucket=self.bucket, Key=key)
            body = obj["Body"].read(MAX_OBJECT_BYTES + 1)
            text = body[:MAX_OBJECT_BYTES].decode("utf-8", errors="replace")
            return text, {"bucket": self.bucket, "key": key, "bytes": len(body[:MAX_OBJECT_BYTES])}
        if name == "orders_lookup":
            order_id = _args(arguments, ["order_id"]).get("order_id")
            if not isinstance(order_id, str) or not ORDER_RE.match(order_id):
                raise Denied("order_id must look like LK-55120")
            try:
                with urllib.request.urlopen(f"{self.orders_url}/orders/{order_id}", timeout=5) as resp:
                    text = resp.read(MAX_OBJECT_BYTES).decode("utf-8", errors="replace")
                    status = resp.status
            except urllib.error.HTTPError as exc:
                text, status = json.dumps({"error": "not found" if exc.code == 404 else "error"}), exc.code
            return text, {"order_id": order_id, "http_status": status}
        raise Denied(f"unknown tool {name!r}")


def from_env(s3):
    return Tools(s3, os.environ["KB_BUCKET"], os.environ.get("ORDERS_URL", "http://127.0.0.1:8081"))
