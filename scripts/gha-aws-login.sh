#!/usr/bin/env bash
# Exchange this job's GitHub OIDC token for short-lived AWS credentials, with the AWS CLI
# already on the runner. Writes the three AWS_* variables to $GITHUB_ENV, masked.
# Needs `permissions: id-token: write` and the role ARN as $1.
set -euo pipefail
role="$1"
token="$(curl -fsS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"])')"
creds="$(aws sts assume-role-with-web-identity --role-arn "$role" \
  --role-session-name "gha-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}" \
  --web-identity-token "$token" --duration-seconds 3600 --output json)"
python3 - "$creds" <<'PY'
import json, os, sys
c = json.loads(sys.argv[1])["Credentials"]
with open(os.environ["GITHUB_ENV"], "a") as env:
    for name, key in (("AWS_ACCESS_KEY_ID", "AccessKeyId"), ("AWS_SECRET_ACCESS_KEY", "SecretAccessKey"),
                      ("AWS_SESSION_TOKEN", "SessionToken")):
        print(f"::add-mask::{c[key]}")
        env.write(f"{name}={c[key]}\n")
PY
echo "assumed $role"
