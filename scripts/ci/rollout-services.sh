#!/usr/bin/env bash
# Roll out ingest and search with the images tagged <sha>, from the prod
# overlay in the current checkout. If either rollout fails, both go back to
# their previous version (kubectl rollout undo) and the script exits 1.
#   scripts/ci/rollout-services.sh <image-repo> <sha>
# Used by release.yml and rollback.yml; needs kubectl (current context) and kustomize.
set -euo pipefail

repo=$1
sha=$2
namespace=${K8S_NAMESPACE:-li}
deployments=(ingest search)

(cd deploy/k8s/overlays/prod && kustomize edit set image "ingest=$repo/ingest:$sha" "search=$repo/search:$sha")
kustomize build deploy/k8s/overlays/prod | kubectl apply -f -

failed=false
for d in "${deployments[@]}"; do
  kubectl -n "$namespace" rollout status "deploy/$d" --timeout=5m || failed=true
done

if $failed; then
  echo "::error::Rollout failed; returning ingest and search to their previous version"
  for d in "${deployments[@]}"; do
    kubectl -n "$namespace" describe "deploy/$d" | tail -n 20 || true
    # Fails harmlessly on the first deploy, when there's no previous version.
    kubectl -n "$namespace" rollout undo "deploy/$d" || true
  done
  for d in "${deployments[@]}"; do
    kubectl -n "$namespace" rollout status "deploy/$d" --timeout=5m || true
  done
  exit 1
fi
