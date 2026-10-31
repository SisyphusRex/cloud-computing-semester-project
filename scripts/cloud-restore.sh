#!/usr/bin/env bash
# List database backups, or restore one (ADR 0004; docs/runbooks/backup-and-restore.md).
#   make cloud-restore ARGS="list"
#   make cloud-restore ARGS="restore <blob> <age key file>"              # into li_restore
#   make cloud-restore ARGS="restore <blob> <age key file> --overwrite"  # replaces li
#
# Runs here, not in the cluster, so the private key never leaves this machine.
# Cloud SQL has no public IP, so this connects through a one-off Job derived from
# the migrate Job (same service account and Cloud SQL proxy) and a port-forward.
# Into li_restore, it compares row counts with li, then drops li_restore; this is
# the routine restore test. It leaves li alone. The environment must be running.
# Needs az, gcloud, kubectl, jq, age, psql and pg_restore (16 or newer).
set -euo pipefail

PROJECT=${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}
REGION=${GCP_REGION:-us-central1}
CLUSTER=${GKE_CLUSTER:-li}
NAMESPACE=${K8S_NAMESPACE:-li}
RESOURCE_GROUP=${BACKUP_RESOURCE_GROUP:-rg-li-backup}
CONTAINER=${BACKUP_CONTAINER:-backups}
CONTEXT="gke_${PROJECT}_${REGION}_${CLUSTER}"
JOB=li-restore-proxy
LOCAL_PORT=${LOCAL_PORT:-15432}
DATABASE=li
RESTORE_DATABASE=li_restore

usage() { sed -n '3,5p' "$0" | sed 's/^# *//' >&2; exit 2; }

[[ -n $PROJECT ]] || { echo "No GCP project: set GCP_PROJECT or run gcloud config set project." >&2; exit 1; }

account() { az storage account list --resource-group "$RESOURCE_GROUP" --query '[0].name' --output tsv; }

list() {
  az storage blob list --account-name "$(account)" --container-name "$CONTAINER" --auth-mode key \
    --query 'sort_by([], &properties.creationTime)[].{name:name, bytes:properties.contentLength, created:properties.creationTime}' \
    --output table
}

kube() { kubectl --context "$CONTEXT" -n "$NAMESPACE" "$@"; }

# The migrate Job, renamed, with its container doing nothing: only the proxy is used.
start_proxy() {
  local image
  gcloud container clusters get-credentials "$CLUSTER" --region "$REGION" --project "$PROJECT" --quiet
  if [[ $(kubectl --context "$CONTEXT" get namespace "$NAMESPACE" \
          -o jsonpath='{.metadata.annotations.lecture-indexer/paused}' 2>/dev/null) == true ]]; then
    echo "The environment is paused: run make cloud-resume first." >&2
    exit 1
  fi
  image=$(kube get deploy/ingest -o jsonpath='{.spec.template.spec.containers[?(@.name=="app")].image}')
  kube delete job "$JOB" --ignore-not-found --wait
  kubectl kustomize deploy/k8s/overlays/prod/migrate |
    kubectl create --dry-run=client -o json -f - |
    jq --arg name "$JOB" --arg image "$image" '
      select(.kind == "Job")
      | .metadata.name = $name
      | .metadata.labels["app.kubernetes.io/name"] = $name
      | .spec.template.metadata.labels["app.kubernetes.io/name"] = $name
      | .spec.backoffLimit = 0
      | .spec.activeDeadlineSeconds = 3600
      | .spec.template.spec.containers |= map(.image = $image | del(.env) | .args = ["exec sleep 3600"])
    ' | kube apply -f -
  echo "Waiting for the Cloud SQL proxy (a new Spot node can take 2-3 minutes)..."
  kube wait --for=condition=Ready pod -l "job-name=$JOB" --timeout=5m
  # kubectl itself, not the kube function: $! must be the process cleanup kills.
  kubectl --context "$CONTEXT" -n "$NAMESPACE" port-forward \
    "$(kube get pods -l "job-name=$JOB" -o name | head -1)" "$LOCAL_PORT:5432" > /dev/null &
  forward=$!
  for _ in $(seq 30); do
    pg_isready -q -h 127.0.0.1 -p "$LOCAL_PORT" && return
    sleep 1
  done
  echo "Couldn't reach the Cloud SQL proxy through the port-forward." >&2
  exit 1
}

row_counts() {  # row_counts <database>: one "table count" line per table, sorted
  local table
  psql -At -d "$1" -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY 1" |
    while read -r table; do
      echo "$table $(psql -At -d "$1" -c "SELECT count(*) FROM \"$table\"")"
    done
}

restore() {
  local blob=${1:-} key=${2:-} mode=${3:-}
  [[ -n $blob && -f $key && ( -z $mode || $mode == --overwrite ) ]] || usage

  if [[ $mode == --overwrite ]]; then
    echo "This replaces everything in the production database '$DATABASE' with $blob."
    echo "Anything written since that backup is lost. Scale ingest and search to 0 first."
    read -r -p "Type 'overwrite $DATABASE' to continue: " answer
    [[ $answer == "overwrite $DATABASE" ]] || { echo "Cancelled." >&2; exit 1; }
  fi

  work=$(mktemp -d)
  trap cleanup EXIT
  echo "Downloading $blob..."
  az storage blob download --account-name "$(account)" --container-name "$CONTAINER" --auth-mode key \
    --name "$blob" --file "$work/backup.age" --only-show-errors --output none
  age --decrypt --identity "$key" --output "$work/backup.dump" "$work/backup.age"

  PGPASSWORD=$(gcloud secrets versions access latest --secret=db-admin-password --project "$PROJECT")
  export PGPASSWORD PGHOST=127.0.0.1 PGPORT=$LOCAL_PORT PGUSER=li_admin PGSSLMODE=disable PGDATABASE=postgres
  start_proxy

  if [[ $mode == --overwrite ]]; then
    pg_restore --clean --if-exists --no-owner --dbname "$DATABASE" "$work/backup.dump"
    echo "Restored $blob into $DATABASE:"
    row_counts "$DATABASE"
    return
  fi

  dropdb --if-exists "$RESTORE_DATABASE"
  createdb "$RESTORE_DATABASE"
  # Not fatal: the comparison below decides whether this worked.
  pg_restore --no-owner --dbname "$RESTORE_DATABASE" "$work/backup.dump" ||
    echo "pg_restore reported errors; see above." >&2
  diff --label "$DATABASE now" --label "$blob" -u <(row_counts "$DATABASE") <(row_counts "$RESTORE_DATABASE") || true
  if ! diff <(row_counts "$DATABASE" | cut -d' ' -f1) <(row_counts "$RESTORE_DATABASE" | cut -d' ' -f1) > /dev/null; then
    echo "The restored tables don't match $DATABASE; $RESTORE_DATABASE is left in place to inspect." >&2
    exit 1
  fi
  dropdb "$RESTORE_DATABASE"
  echo "Restore test finished: $blob. Differences above are rows written since the backup."
}

cleanup() {
  [[ -n ${forward:-} ]] && kill "$forward" 2> /dev/null || true
  kube delete job "$JOB" --ignore-not-found --wait=false > /dev/null 2>&1 || true
  rm -rf "$work"
}

case ${1:-} in
  list) list ;;
  restore) shift; restore "$@" ;;
  *) usage ;;
esac
