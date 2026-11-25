#!/usr/bin/env bash
# Sign the Azure CLI in as the deploy identity with this job's GitHub OIDC token. No secret is
# stored anywhere: Entra ID trusts the token because the identity has a federated credential
# for this repository's main branch. Needs `permissions: id-token: write` and AZURE_CLIENT_ID,
# AZURE_TENANT_ID and AZURE_SUBSCRIPTION_ID in the environment.
set -euo pipefail
token="$(curl -fsS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"])')"
echo "::add-mask::$token"
# Print the token's routing claims (not the token) so a federated-credential mismatch is visible.
python3 - "$token" <<'PY'
import base64, json, sys
part = sys.argv[1].split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))
print({k: claims.get(k) for k in ("iss", "aud", "sub", "job_workflow_ref")})
PY
az login --service-principal --username "$AZURE_CLIENT_ID" --tenant "$AZURE_TENANT_ID" \
  --federated-token "$token" --allow-no-subscriptions --output none
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
echo "signed in as $(az account show --query user.name -o tsv)"
