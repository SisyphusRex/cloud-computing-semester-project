#!/usr/bin/env bash
# Run the migrate Job (deploy/k8s/overlays/prod/migrate) with the ingest image
# tagged <sha>, and wait for it to finish. Exits 1, with its logs, if it fails.
#   scripts/ci/run-migrations.sh <image-repo> <sha>
# Used by release.yml; needs kubectl (current context) and kustomize.
set -euo pipefail

repo=$1
sha=$2
namespace=${K8S_NAMESPACE:-li}

(cd deploy/k8s/overlays/prod/migrate && kustomize edit set image "ingest=$repo/ingest:$sha")
# The migrate overlay doesn't include the Namespace.
kubectl apply -f deploy/k8s/base/namespace.yaml
# A Job's pod template can't be changed, so replace the previous run.
kubectl -n "$namespace" delete job migrate --ignore-not-found --wait
kustomize build deploy/k8s/overlays/prod/migrate | kubectl apply -f -

# The Job gives up after 600 s (activeDeadlineSeconds).
status=""
for _ in $(seq 132); do
  status=$(kubectl -n "$namespace" get job migrate \
    -o jsonpath='{.status.conditions[?(@.status=="True")].type}')
  [[ $status == *Complete* || $status == *Failed* ]] && break
  sleep 5
done
kubectl -n "$namespace" logs job/migrate -c migrate --tail=100 || true
if [[ $status != *Complete* ]]; then
  kubectl -n "$namespace" describe job migrate
  echo "::error::Migrations did not complete (${status:-timed out})"
  exit 1
fi
