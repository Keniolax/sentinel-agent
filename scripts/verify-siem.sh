#!/usr/bin/env bash
# Prove that one agent run reached the SIEM: the run's own log lines (from the job's console
# logs) and the blob reads its identity made (from the storage account's resource logs). Runs
# a read-only probe on the SIEM VM through Run Command and polls until all four counts are
# above zero.
#   scripts/verify-siem.sh <run_id> [timeout_minutes]
set -euo pipefail
run_id="${1:?usage: scripts/verify-siem.sh <run_id> [timeout_minutes]}"
limit="${2:-30}"
. "$(dirname "$0")/lab.sh"
agent="$(az identity show -g "$RG" -n id-sentinel-agent --query principalId -o tsv)"
probe=$(cat <<PROBE
cd /opt/home-soc-lab && export COMPOSE_FILE=compose.yaml:/opt/sentinel/compose.sentinel.yaml
m() { docker compose exec -T wazuh.manager "\$@"; }
a=\$(m grep -c '$run_id' /var/ossec/logs/archives/archives.json || true)
b=\$(m grep '"OperationName":"GetBlob"' /var/ossec/logs/archives/archives.json | grep -c '$agent' || true)
r1=\$(m grep -c '"id":"100810"' /var/ossec/logs/alerts/alerts.json || true)
r2=\$(m grep '"id":"100811"' /var/ossec/logs/alerts/alerts.json | grep -c '$run_id' || true)
echo "agent_lines=\$a agent_blob_reads=\$b rule_100810_alerts=\$r1 rule_100811_run_alerts=\$r2"
PROBE
)
deadline=$(( $(date +%s) + limit * 60 ))
while :; do
  line="$(az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript --scripts "$probe" \
    --query 'value[0].message' -o tsv | grep -o 'agent_lines=.*' | tail -1 || true)"
  echo "$(date -u +%H:%M:%S) ${line:-no answer from the VM yet}"
  if [[ "$line" =~ agent_lines=([1-9][0-9]*)\ agent_blob_reads=([1-9][0-9]*)\ rule_100810_alerts=([1-9][0-9]*)\ rule_100811_run_alerts=([1-9][0-9]*) ]]; then
    echo "PASS: run $run_id, its identity's blob reads, and both capstone rules are in the SIEM"; exit 0
  fi
  [ "$(date +%s)" -lt "$deadline" ] || { echo "FAIL: not in the SIEM after $limit minutes"; exit 1; }
  sleep 60
done
