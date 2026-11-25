#!/usr/bin/env bash
# Push siem/local_rules.xml to the running SIEM VM and reload the Wazuh manager, without
# rebuilding the VM. The manager mounts /opt/sentinel/local_rules.xml read-only and copies it
# to its rules directory at start, so this writes the host file, reinstalls it in the
# container, and restarts the manager. Run it after editing the rules.
#   scripts/update-rules.sh
set -euo pipefail
. "$(dirname "$0")/lab.sh"
rules_b64="$(base64 < "$(dirname "$0")/../siem/local_rules.xml" | tr -d '\n')"
script=$(cat <<SH
set -e
echo '$rules_b64' | base64 -d > /opt/sentinel/local_rules.xml
cd /opt/home-soc-lab && export COMPOSE_FILE=compose.yaml:/opt/sentinel/compose.sentinel.yaml
docker compose exec -T wazuh.manager install -o wazuh -g wazuh -m 0640 \
  /opt/sentinel/local_rules.xml /var/ossec/etc/rules/local_rules.xml
docker compose exec -T wazuh.manager /var/ossec/bin/wazuh-control restart >/dev/null
sleep 5
docker compose exec -T wazuh.manager /var/ossec/bin/wazuh-logtest -q <<'T' 2>&1 | tail -2 || true
{"sentinel_source":"storage","OperationName":"GetBlob","StatusCode":"403","ObjectKey":"/x/finance/records/payroll-2026-11.csv","StatusText":"AuthorizationPermissionMismatch"}
T
echo RULES_RELOADED
SH
)
az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript --scripts "$script" \
  --query 'value[0].message' -o tsv
