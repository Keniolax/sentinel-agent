# Shared settings for the operator scripts. Source it; override any name with the environment.
RG="${RG:-rg-sentinel-lab}"
JOB="${JOB:-caj-sentinel-agent}"
WORKSPACE="${WORKSPACE:-log-sentinel}"
VM="${VM:-vm-sentinel-siem}"
SUB="${SUB:-$(az account show --query id -o tsv)}"
ARM="https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers"

# Run one KQL query against the lab workspace and print the rows as JSON lines.
la_query() {
  local ws body
  ws="$(az rest --method get --url "$ARM/Microsoft.OperationalInsights/workspaces/$WORKSPACE?api-version=2023-09-01" --query properties.customerId -o tsv)"
  body="$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$1")"
  az rest --method post --resource https://api.loganalytics.io \
    --url "https://api.loganalytics.azure.com/v1/workspaces/$ws/query" --body "$body" -o json |
    python3 -c '
import json, sys
t = json.load(sys.stdin)["tables"][0]
names = [c["name"] for c in t["columns"]]
for row in t["rows"]:
    print(json.dumps(dict(zip(names, row))))'
}
