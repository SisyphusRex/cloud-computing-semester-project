#!/bin/sh
# Dump the database, encrypt it to a public key, and upload it to Azure Blob
# Storage with a create-only SAS (ADR 0004). Runs in the backup CronJob.
#   PG* variables          where to connect (libpq), except the password
#   BACKUP_AGE_RECIPIENT   age public key; the private key stays offline
#   BACKUP_CONTAINER_URL   https://<account>.blob.core.windows.net/<container>
#   /secrets/...           db-admin-password and backup-sas
set -euo pipefail

SECRETS_DIR=${SECRETS_DIR:-/secrets}
WORK_DIR=${WORK_DIR:-/work}
name="li-$(date -u +%Y-%m-%dT%H%M%SZ).dump.age"
file=$WORK_DIR/$name

# The same JSON as li_common.logs, so Cloud Logging reads the severity.
log() {  # log <severity> <event> <extra json fields>
  printf '{"severity":"%s","message":"%s","event":"%s","name":"%s"%s}\n' "$1" "$2" "$2" "$name" "${3:-}"
}

on_exit() {
  status=$?
  rm -f "$file"
  [ "$status" -eq 0 ] || log ERROR backup_failed
}
trap on_exit EXIT

PGPASSWORD=$(cat "$SECRETS_DIR/db-admin-password")
export PGPASSWORD
# --no-owner: a restore runs as li_admin. Grants stay, for the services' roles.
pg_dump --format=custom --no-owner | age --recipient "$BACKUP_AGE_RECIPIENT" --output "$file"
unset PGPASSWORD

# An empty dump still encrypts to a few hundred bytes, and pipefail covers a
# failed pg_dump, so this only guards against an unexpectedly empty result.
bytes=$(wc -c < "$file")
if [ "$bytes" -lt 1024 ]; then
  echo "backup is only $bytes bytes" >&2
  exit 1
fi

# On stdin, not in the arguments, so the SAS can't show up in a process list.
# Without --retry-all-errors, because a retried create fails if the first worked.
printf 'url = "%s/%s?%s"\n' "$BACKUP_CONTAINER_URL" "$name" "$(cat "$SECRETS_DIR/backup-sas")" |
  curl --config - --fail --silent --show-error --retry 3 --output /dev/null \
    --header 'x-ms-blob-type: BlockBlob' --upload-file "$file"

log INFO backup_succeeded ",\"bytes\":$bytes"
