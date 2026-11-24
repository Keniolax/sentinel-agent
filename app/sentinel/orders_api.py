"""A mock internal orders API. It listens on loopback inside the task and answers GET /orders/<id>.

It stands in for an internal service the agent may call. Each request is one JSON log line.
"""

import json
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ORDERS = json.loads((Path(__file__).with_name("orders.json")).read_text(encoding="utf-8"))
PATH_RE = re.compile(r"^/orders/(LK-\d{5})$")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        print(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "app": "orders-api",
                          "event": "request", "method": self.command, "path": self.path[:200], "status": code},
                         sort_keys=True), flush=True)

    def do_GET(self):
        m = PATH_RE.match(self.path)
        if m and m.group(1) in ORDERS:
            self._send(200, ORDERS[m.group(1)])
        else:
            self._send(404, {"error": "not found"})


def serve(host="127.0.0.1", port=8081):
    ThreadingHTTPServer((host, port), Handler).serve_forever()
