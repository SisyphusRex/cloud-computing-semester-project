#!/usr/bin/env bash
# Create the SAS the backup CronJob uploads with, and store it in Secret Manager
# (ADR 0004). Create-only: it can add blobs, but not read, list, overwrite or
# delete them. It's made here so that it never lands in Terraform state. Running
# this again replaces it; the next backup picks up the new one.
#   make cloud-backup-sas
# Needs az (signed in with access to rg-li-backup) and gcloud.
set -euo pipefail

PROJECT=${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}
RESOURCE_GROUP=${BACKUP_RESOURCE_GROUP:-rg-li-backup}
CONTAINER=${BACKUP_CONTAINER:-backups}
SECRET=backup-sas

[[ -n $PROJECT ]] || { echo "No GCP project: set GCP_PROJECT or run gcloud config set project." >&2; exit 1; }

account=$(az storage account list --resource-group "$RESOURCE_GROUP" --query '[0].name' --output tsv)
[[ -n $account ]] || { echo "No storage account in $RESOURCE_GROUP: apply infra/terraform/bootstrap first." >&2; exit 1; }

# In the environment, not an argument, so the key can't show up in a process list.
AZURE_STORAGE_KEY=$(az storage account keys list --resource-group "$RESOURCE_GROUP" \
  --account-name "$account" --query '[0].value' --output tsv)
export AZURE_STORAGE_KEY

expiry=$(date -u -d '+1 year' +%Y-%m-%dT%H:%MZ)
az storage container generate-sas --account-name "$account" --name "$CONTAINER" \
  --permissions c --https-only --expiry "$expiry" --output tsv |
  tr -d '\n' |
  gcloud secrets versions add "$SECRET" --project "$PROJECT" --data-file=- --quiet

echo "Stored a new version of $SECRET. The SAS expires on $expiry: renew it before then."
