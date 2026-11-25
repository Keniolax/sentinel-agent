#!/usr/bin/env python3
"""Copy the lab's Azure logs into a file that Wazuh reads, one JSON object per line.

Runs on the SIEM host every minute (sentinel-collector.timer). It signs in with the VM's
user-assigned managed identity through the instance metadata service, so the host holds no
secret. Wazuh's own azure-logs module needs an app registration with a client secret, which
this design avoids.

It asks Log Analytics for every row ingested since the last checkpoint from three tables,
writes each row to /var/log/sentinel/azure.json, and then moves the checkpoint. Rows are
selected by ingestion time, not event time, so a row that arrives late is still collected.
"""

import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

WORKSPACE_ID = os.environ.get("WORKSPACE_ID", "")  # the workspace's customer ID (a GUID)
CLIENT_ID = os.environ.get("CLIENT_ID", "")  # the SIEM identity's client ID
OUT = os.environ.get("OUT", "/var/log/sentinel/azure.json")
STATE = os.environ.get("STATE", "/var/lib/sentinel-collector/checkpoint")
IMDS = "http://169.254.169.254/metadata/identity/oauth2/token"
API = "https://api.loganalytics.azure.com/v1/workspaces/{}/query"
MAX_ROWS = 5000

QUERY = """
let since = datetime({since});
union isfuzzy=true
  (ContainerAppConsoleLogs
   | extend sentinel_source = "job",
            job = tostring(column_ifexists("JobName", column_ifexists("ContainerAppName", ""))),
            execution = tostring(column_ifexists("ContainerGroupName", "")),
            line = tostring(column_ifexists("Log", ""))
   | project TimeGenerated, sentinel_source, job, execution, line),
  (StorageBlobLogs
   | extend sentinel_source = "storage"
   | project TimeGenerated, sentinel_source, AccountName, OperationName, StatusCode, StatusText,
             ObjectKey, CallerIpAddress, RequesterObjectId, AuthenticationType),
  (AzureActivity
   | extend sentinel_source = "activity"
   | project TimeGenerated, sentinel_source, OperationNameValue, ActivityStatusValue, Caller,
             ResourceGroup, ResourceId = _ResourceId)
| extend ingested = ingestion_time()
| where ingested > since
| order by ingested asc
| take {max_rows}
"""


def token():
    url = IMDS + "?" + urllib.parse.urlencode(
        {"api-version": "2018-02-01", "resource": "https://api.loganalytics.io", "client_id": CLIENT_ID})
    req = urllib.request.Request(url, headers={"Metadata": "true"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.load(resp)["access_token"]


def query(since):
    body = json.dumps({"query": QUERY.format(since=since, max_rows=MAX_ROWS)}).encode()
    req = urllib.request.Request(API.format(WORKSPACE_ID), data=body, method="POST", headers={
        "Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        table = json.load(resp)["tables"][0]
    names = [c["name"] for c in table["columns"]]
    return [dict(zip(names, row)) for row in table["rows"]]


def shape(row):
    """Drop empty columns. Parse the agent's own JSON line into a nested "sentinel" object so
    Wazuh rules can match its fields. ("agent" is taken: Wazuh uses it for its own agent.)"""
    out = {k: v for k, v in row.items() if v not in (None, "")}
    if out.get("sentinel_source") == "job" and str(out.get("line", "")).startswith("{"):
        try:
            parsed = json.loads(out["line"])
        except ValueError:
            parsed = None
        if isinstance(parsed, dict):
            out["sentinel"] = parsed
            del out["line"]
    return out


def main():
    try:
        with open(STATE) as f:
            since = f.read().strip()
    except FileNotFoundError:
        since = (datetime.now(timezone.utc) - timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
    rows = query(since)
    with open(OUT, "a") as out:
        for row in rows:
            out.write(json.dumps(shape(row), sort_keys=True) + "\n")
    if rows:
        os.makedirs(os.path.dirname(STATE), exist_ok=True)
        with open(STATE + ".tmp", "w") as f:
            f.write(rows[-1]["ingested"])
        os.replace(STATE + ".tmp", STATE)
    print(f"collected {len(rows)} rows since {since}", file=sys.stderr)


if __name__ == "__main__":
    main()
