#!/usr/bin/env bash
# The second lock, tested on its own. Starts one execution of the agent's job that skips the
# agent and its key check, and asks storage for the payroll file with the job's own identity.
# Azure RBAC must refuse it (403 AuthorizationPermissionMismatch). Exit 0 means refused.
#   scripts/probe-finance.sh
set -euo pipefail
. "$(dirname "$0")/lab.sh"
api="api-version=2024-03-01"
run_id="probe-$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM"
template="$(az rest --method get --url "$ARM/Microsoft.App/jobs/$JOB?$api" --query properties.template -o json)"
body="$(python3 - "$template" "$run_id" <<'PY'
import json, sys
t, run_id = json.loads(sys.argv[1]), sys.argv[2]
c = t["containers"][0]
code = (
    "import json, os\n"
    "from sentinel.blob import BlobStore\n"
    "s = BlobStore.from_managed_identity(os.environ['KB_ACCOUNT_URL'], 'finance', os.environ['AZURE_CLIENT_ID'])\n"
    "try:\n"
    "    s.get('records/payroll-2026-11.csv', 64)\n"
    "    r = 'read'\n"
    "except Exception as e:\n"
    "    r = getattr(e, 'error_code', None) or type(e).__name__\n"
    "print(json.dumps({'app': 'sentinel-agent', 'event': 'finance_probe', 'run_id': os.environ['RUN_ID'], 'result': str(r)}))\n"
)
c["command"] = ["python3", "-c", code]
c["args"] = []
c["env"] = [e for e in c.get("env", []) if e["name"] != "RUN_ID"] + [{"name": "RUN_ID", "value": run_id}]
print(json.dumps({"containers": [c]}))
PY
)"
execution="$(az rest --method post --url "$ARM/Microsoft.App/jobs/$JOB/start?$api" --body "$body" --query name -o tsv)"
echo "run_id=$run_id execution=$execution"
for _ in $(seq 1 40); do
  line="$(la_query "ContainerAppConsoleLogs | where Log has '$run_id' | project Log" | head -1)"
  [ -n "$line" ] && break
  sleep 20
done
result="$(python3 -c 'import json,sys; print(json.loads(json.loads(sys.argv[1])["Log"])["result"])' "$line")"
echo "result=$result"
[ "$result" = AuthorizationPermissionMismatch ]
