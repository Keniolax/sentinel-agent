#!/usr/bin/env bash
# Copy the bootstrap stack's outputs into GitHub repository variables (not secrets: they are
# IDs and names). Run after `terraform apply` in infra/bootstrap.
set -euo pipefail
cd "$(dirname "$0")/../infra/bootstrap"
terraform output -json | python3 -c '
import json, sys
for k, v in json.load(sys.stdin).items():
    print(k.upper(), v["value"])' | while read -r name value; do
  gh variable set "$name" --body "$value"
  echo "set $name"
done
