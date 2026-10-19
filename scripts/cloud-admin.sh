#!/usr/bin/env bash
# Run li-admin (user accounts; ADR 0002) against the production database.
#   make cloud-create-superuser EMAIL=you@example.com
#   make cloud-admin ARGS="add-user someone@example.com --role professor"
#   make cloud-admin ARGS=list
#   (or scripts/cloud-admin.sh <li-admin arguments>)
#
# Only li-admin, with database-admin credentials, can make a superuser. It runs
# as a one-off Job derived from the migrate Job (same service account, db-admin
# secret and Cloud SQL proxy sidecar), using the ingest image that's deployed now,
# so the CLI matches the schema. The environment must be running (make
# cloud-resume). Needs gcloud, kubectl and jq. DRY_RUN=1 prints the Job instead.
set -euo pipefail

(( $# )) || { echo "usage: $0 <li-admin arguments>, e.g. create-superuser EMAIL" >&2; exit 2; }

PROJECT=${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}
REGION=${GCP_REGION:-us-central1}
CLUSTER=${GKE_CLUSTER:-li}
NAMESPACE=${K8S_NAMESPACE:-li}
CONTEXT="gke_${PROJECT}_${REGION}_${CLUSTER}"
JOB=li-admin

[[ -n $PROJECT ]] || { echo "No GCP project: set GCP_PROJECT or run gcloud config set project." >&2; exit 1; }

if [[ ${DRY_RUN:-0} == 1 ]]; then
  image="ingest:DEPLOYED"
else
  gcloud container clusters get-credentials "$CLUSTER" --region "$REGION" --project "$PROJECT" --quiet
  if [[ $(kubectl --context "$CONTEXT" get namespace "$NAMESPACE" \
          -o jsonpath='{.metadata.annotations.lecture-indexer/paused}' 2>/dev/null) == true ]]; then
    echo "The environment is paused: run make cloud-resume first." >&2
    exit 1
  fi
  image=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get deploy/ingest \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="app")].image}')
fi

# The migrate Job, renamed, running li-admin "$@" in the deployed image. The
# arguments are passed as sh positional parameters, so they're never re-parsed.
job=$(kubectl kustomize deploy/k8s/overlays/prod/migrate |
  kubectl create --dry-run=client -o json -f - |
  jq --arg name "$JOB" --arg image "$image" --argjson args "$(jq -n '$ARGS.positional' --args -- "$@")" '
    select(.kind == "Job")
    | .metadata.name = $name
    | .metadata.labels["app.kubernetes.io/name"] = $name
    | .spec.template.metadata.labels["app.kubernetes.io/name"] = $name
    | .spec.backoffLimit = 0
    | .spec.activeDeadlineSeconds = 300
    | .spec.template.spec.containers |= map(
        if .name == "migrate" then
          .name = "li-admin" | .image = $image
          | .env |= map(select(.name != "LI_MIGRATE_GRANTS"))
          | .args = ["PGPASSWORD=\"$(cat /secrets/db-admin-password)\" exec li-admin \"$@\"", "li-admin"] + $args
        else . end)
  ')

if [[ ${DRY_RUN:-0} == 1 ]]; then
  echo "$job"
  exit 0
fi

kube() { kubectl --context "$CONTEXT" -n "$NAMESPACE" "$@"; }
kube delete job "$JOB" --ignore-not-found --wait
kube apply -f - <<< "$job"
echo "Waiting for li-admin (usually under a minute; a new Spot node can take 2-3)..."
status=""
for _ in $(seq 66); do
  status=$(kube get job "$JOB" -o jsonpath='{.status.conditions[?(@.status=="True")].type}')
  [[ $status == *Complete* || $status == *Failed* ]] && break
  sleep 5
done
kube logs "job/$JOB" -c li-admin --tail=200 || true
if [[ $status != *Complete* ]]; then
  echo "li-admin did not complete (${status:-timed out}); see: kubectl -n $NAMESPACE describe job $JOB" >&2
  exit 1
fi
kube delete job "$JOB" --wait=false
