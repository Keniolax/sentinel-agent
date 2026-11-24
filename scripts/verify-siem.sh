#!/usr/bin/env bash
# Prove that one agent run reached the SIEM: its own log lines (through CloudWatch Logs)
# and the CloudTrail data event for the object it read (through the trail bucket).
# Runs a read-only command on the SIEM host through SSM and polls until both appear.
#   scripts/verify-siem.sh <run_id> [timeout_minutes]
set -euo pipefail
run_id="${1:?usage: scripts/verify-siem.sh <run_id> [timeout_minutes]}"
limit="${2:-30}"
instance="$(terraform -chdir="$(dirname "$0")/../infra/main" output -raw siem_instance_id)"
kb_bucket="$(terraform -chdir="$(dirname "$0")/../infra/main" output -raw kb_bucket)"
probe=$(cat <<PROBE
cd /opt/home-soc-lab && export COMPOSE_FILE=compose.yaml:/opt/sentinel/compose.sentinel.yaml
a=\$(docker compose exec -T wazuh.manager grep -c '$run_id' /var/ossec/logs/archives/archives.json || true)
c=\$(docker compose exec -T wazuh.manager grep -c '"eventName":"GetObject".*$kb_bucket\|$kb_bucket.*"eventName":"GetObject"' /var/ossec/logs/archives/archives.json || true)
r=\$(docker compose exec -T wazuh.manager grep -c '"id":"100810"' /var/ossec/logs/alerts/alerts.json || true)
echo "agent_lines=\$a cloudtrail_getobject=\$c rule_100810_alerts=\$r"
PROBE
)
deadline=$(( $(date +%s) + limit * 60 ))
while :; do
  cmd="$(aws ssm send-command --instance-ids "$instance" --document-name AWS-RunShellScript \
    --parameters "commands=[$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$probe")]" \
    --query Command.CommandId --output text)"
  sleep 5
  aws ssm wait command-executed --command-id "$cmd" --instance-id "$instance" 2>/dev/null || true
  line="$(aws ssm get-command-invocation --command-id "$cmd" --instance-id "$instance" \
    --query StandardOutputContent --output text | tail -1)"
  echo "$(date -u +%H:%M:%S) $line"
  if [[ "$line" =~ agent_lines=([1-9][0-9]*)\ cloudtrail_getobject=([1-9][0-9]*) ]]; then
    echo "PASS: run $run_id and its CloudTrail data event are in the SIEM"; exit 0
  fi
  [ "$(date +%s)" -lt "$deadline" ] || { echo "FAIL: not in the SIEM after $limit minutes"; exit 1; }
  sleep 60
done
