#!/usr/bin/env bash
# Week 19: read the SIEM and show which detection fired on which step of the attack chain.
# Run it after attack/run-chain.sh. It polls the Wazuh manager on the SIEM VM through Run
# Command (the logs take a few minutes to reach the workspace and then the collector).
#   attack/evidence.sh <tag>        (tag is printed by run-chain.sh, e.g. wk19-2026...Z)
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lab.sh
tag="${1:?usage: attack/evidence.sh <tag>}"
ids="out/week19/$tag.ids"
[ -f "$ids" ] && . "$ids" || { echo "no $ids; pass the tag run-chain.sh printed"; exit 1; }
limit="${2:-25}"

probe=$(cat <<PROBE
cd /opt/home-soc-lab && export COMPOSE_FILE=compose.yaml:/opt/sentinel/compose.sentinel.yaml
m() { docker compose exec -T wazuh.manager "\$@"; }
A=/var/ossec/logs/alerts/alerts.json
d1=\$(m grep -c '"id":"100820"' \$A || true)
d1s=\$(m grep -c '"id":"100821"' \$A || true)
d2w=\$(m grep '"id":"100822"' \$A | grep -c '$weak_run' || true)
d2p=\$(m grep '"id":"100822"' \$A | grep -c '$prod_run' || true)
d3=\$(m grep -c '"id":"100823"' \$A || true)
d4=\$(m grep -c '"id":"100824"' \$A || true)
echo "d1=\$d1 d1s=\$d1s d2w=\$d2w d2p=\$d2p d3=\$d3 d4=\$d4"
PROBE
)
deadline=$(( $(date +%s) + limit * 60 ))
while :; do
  line="$(az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript --scripts "$probe" \
    --query 'value[0].message' -o tsv | grep -o 'd1=.*' | tail -1 || true)"
  echo "$(date -u +%H:%M:%S) ${line:-no answer from the VM yet}"
  eval "${line:-d1=0 d1s=0 d2w=0 d2p=0 d3=0 d4=0}"
  # The chain is proven when: finance access is caught (100820), the successful read is caught
  # and ranked top (100821), the weak agent's non-kb tool call is caught (100822), the
  # production run did NOT trip 100822 (lock 1 held), Run Command is caught (100823), and the
  # finance role grant is caught (100824).
  if [ "$d1" -ge 1 ] && [ "$d1s" -ge 1 ] && [ "$d2w" -ge 1 ] && [ "$d2p" -eq 0 ] \
     && [ "$d3" -ge 1 ] && [ "$d4" -ge 1 ]; then
    echo
    echo "PASS — attack chain to detection:"
    echo "  A inject + tool misuse   rule 100822 fired on the weak run ($d2w), quiet on production ($d2p)"
    echo "  B finance read (exfil)   rule 100820 any access ($d1), rule 100821 successful read ($d1s)"
    echo "  C Run Command            rule 100823 ($d3)"
    echo "  C role-assignment abuse  rule 100824 on the finance grant ($d4)"
    exit 0
  fi
  [ "$(date +%s)" -lt "$deadline" ] || { echo "FAIL: not all detections in the SIEM after $limit min"; exit 1; }
  sleep 60
done
