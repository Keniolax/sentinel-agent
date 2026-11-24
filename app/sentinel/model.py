"""The model client: Ollama's chat API with tools, a fixed temperature and a fixed seed."""

import json
import os
import urllib.request

# Ollama cuts a prompt that is longer than the context window from the front, which would
# drop the system prompt. 8192 tokens holds four tool results with room to spare.
NUM_CTX = 8192


class Ollama:
    def __init__(self, model=None, host=None, temperature=0.0, seed=42):
        self.name = model or os.environ.get("MODEL", "qwen2.5:1.5b")
        self.host = (host or os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")).rstrip("/")
        self.temperature = float(os.environ.get("TEMPERATURE", temperature))
        self.seed = int(os.environ.get("SEED", seed))

    def chat(self, messages, tools):
        body = json.dumps({
            "model": self.name, "stream": False, "messages": messages, "tools": tools,
            "options": {"temperature": self.temperature, "seed": self.seed, "num_ctx": NUM_CTX},
        }).encode()
        req = urllib.request.Request(f"{self.host}/api/chat", data=body,
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=600) as resp:
            return json.load(resp)["message"]
