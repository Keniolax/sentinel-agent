#!/usr/bin/env bash
# Ask the Sentinel Agent one question: start one execution of the Container Apps job with the
# question and a run ID, wait for it to finish, then print its log lines from Log Analytics.
#   scripts/ask.sh "What is your return policy?"
set -euo pipefail
question="${1:?usage: scripts/ask.sh \"question\"}"
. "$(dirname "$0")/lab.sh"
run_id="ask-$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM"
api="api-version=2024-03-01"

# The start request carries the whole container template, with QUESTION and RUN_ID set.
template="$(az rest --method get --url "$ARM/Microsoft.App/jobs/$JOB?$api" --query properties.template -o json)"
body="$(python3 - "$template" "$question" "$run_id" <<'PY'
import json, sys
t, question, run_id = json.loads(sys.argv[1]), sys.argv[2], sys.argv[3]
c = t["containers"][0]
env = [e for e in c.get("env", []) if e["name"] not in ("QUESTION", "RUN_ID")]
c["env"] = env + [{"name": "QUESTION", "value": question}, {"name": "RUN_ID", "value": run_id}]
print(json.dumps({"containers": [c], "initContainers": t.get("initContainers") or []}))
PY
)"
execution="$(az rest --method post --url "$ARM/Microsoft.App/jobs/$JOB/start?$api" --body "$body" --query name -o tsv)"
echo "run_id=$run_id execution=$execution"

while :; do
  status="$(az rest --method get --url "$ARM/Microsoft.App/jobs/$JOB/executions/$execution?$api" --query properties.status -o tsv)"
  case "$status" in Succeeded|Failed|Stopped|Degraded) break ;; esac
  sleep 10
done
echo "execution $status"

# Console logs reach the workspace a few minutes after the execution ends. A failed
# execution never writes an answer line, so wait less for it.
tries=30; [ "$status" = Succeeded ] || tries=6
for _ in $(seq 1 "$tries"); do
  lines="$(la_query "ContainerAppConsoleLogs | where ContainerGroupName startswith '$execution-' | order by TimeGenerated asc | project Log")"
  if python3 -c '
import json, sys
logs = [json.loads(line)["Log"] for line in sys.stdin if line.strip()]
sys.exit(0 if any(l.startswith("{") and json.loads(l).get("event") == "answer" for l in logs) else 1)' <<<"$lines"; then break; fi
  sleep 20
done
python3 -c '
import json, sys
for line in sys.stdin:
    print(json.loads(line)["Log"])' <<<"$lines"
[ "$status" = Succeeded ]
