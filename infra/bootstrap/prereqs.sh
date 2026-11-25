#!/usr/bin/env bash
# Run once by the subscription owner, before `terraform apply` in this folder. Registers the
# resource providers the lab uses and the EncryptionAtHost feature for the SIEM's disks.
# Registration is free and creates no resource.
set -euo pipefail
for ns in Microsoft.App Microsoft.ContainerRegistry Microsoft.Compute Microsoft.Insights \
  Microsoft.KeyVault Microsoft.ManagedIdentity Microsoft.Network Microsoft.OperationalInsights \
  Microsoft.Storage; do
  az provider register --namespace "$ns" --wait
  echo "$ns $(az provider show --namespace "$ns" --query registrationState -o tsv)"
done
az feature register --namespace Microsoft.Compute --name EncryptionAtHost -o none
until [ "$(az feature show --namespace Microsoft.Compute --name EncryptionAtHost --query properties.state -o tsv)" = Registered ]; do
  echo "waiting for EncryptionAtHost"; sleep 30
done
az provider register --namespace Microsoft.Compute --wait
echo "EncryptionAtHost Registered"
