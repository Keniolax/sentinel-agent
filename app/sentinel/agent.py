"""The Sentinel Agent: answers one customer-support question with three read-only tools.

Every model request, tool call and answer is written as one JSON line on stdout. Container
Apps ships stdout to Log Analytics (ContainerAppConsoleLogs), where the SIEM's collector reads it.
"""

import hashlib
import json
import sys
import time
import uuid

from .tools import TOOL_SPECS, Denied

SYSTEM = (
    "You are the support assistant for Larkspur Outdoor, an online shop. Answer the customer's "
    "question using the tools: kb_list and kb_get read help articles, orders_lookup reads one "
    "order's status. Use only what the tools return. Keep the answer under 120 words."
)
MAX_STEPS = 4
MAX_QUESTION = 2000


def log(event, **fields):
    line = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "app": "sentinel-agent", "event": event}
    line.update(fields)
    print(json.dumps(line, sort_keys=True), file=sys.stdout, flush=True)


def sha256(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def ask(question, model, tools, run_id=None):
    """Answer one question. Returns the answer text."""
    run_id = run_id or uuid.uuid4().hex[:16]
    question = question[:MAX_QUESTION]
    log("question", run_id=run_id, question_sha256=sha256(question), question_chars=len(question),
        model=model.name)
    messages = [{"role": "system", "content": SYSTEM}, {"role": "user", "content": question}]
    for step in range(1, MAX_STEPS + 1):
        reply = model.chat(messages, TOOL_SPECS)
        calls = reply.get("tool_calls") or []
        log("model_reply", run_id=run_id, step=step, tool_calls=len(calls),
            content_chars=len(reply.get("content") or ""))
        if not calls:
            answer = (reply.get("content") or "").strip()
            log("answer", run_id=run_id, step=step, answer_sha256=sha256(answer), answer_chars=len(answer))
            return answer
        messages.append({"role": "assistant", "content": reply.get("content") or "", "tool_calls": calls})
        for call in calls:
            fn = call.get("function", {}) if isinstance(call, dict) else {}
            name, arguments = fn.get("name"), fn.get("arguments", {})
            try:
                result, fields = tools.run(name, arguments)
                log("tool_call", run_id=run_id, step=step, tool=name, args=arguments, decision="allowed", **fields)
            except Denied as exc:
                result = json.dumps({"error": str(exc)})
                log("tool_call", run_id=run_id, step=step, tool=name, args=arguments, decision="denied",
                    reason=str(exc))
            except Exception as exc:  # an Azure or network error: the model gets no detail
                result = json.dumps({"error": "the tool failed"})
                log("tool_call", run_id=run_id, step=step, tool=name, args=arguments, decision="error",
                    reason=type(exc).__name__)
            messages.append({"role": "tool", "content": result, "tool_name": name})
    log("answer", run_id=run_id, step=MAX_STEPS, answer_sha256=sha256(""), answer_chars=0, stopped="max_steps")
    return "I could not finish that request."
