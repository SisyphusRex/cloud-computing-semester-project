#!/usr/bin/env bash
# Deploy an image to the Cloud Run frontend without sending it traffic, check
# the new revision on its own "candidate" URL, then move all traffic to it.
# If the check fails, traffic stays on the current revision and this exits 1.
#   scripts/ci/deploy-frontend.sh <image>
# Used by release.yml and rollback.yml; needs gcloud and jq.
set -euo pipefail

image=$1
service=${FRONTEND_SERVICE:-li-frontend}
region=${GCP_REGION:?set GCP_REGION}

gcloud run deploy "$service" --image "$image" --region "$region" \
  --no-traffic --tag candidate --quiet

candidate=$(gcloud run services describe "$service" --region "$region" --format=json |
  jq -r '.status.traffic[] | select(.tag == "candidate") | .url')
echo "Candidate revision: $candidate"

ok=false
for _ in $(seq 12); do
  if [[ $(curl -s "$candidate/health") == ok ]] && curl -sf "$candidate/" | grep -q 'id="root"'; then
    ok=true
    break
  fi
  sleep 5
done
if ! $ok; then
  echo "::error::The new frontend revision failed its check at $candidate; traffic stays on the current revision"
  exit 1
fi

gcloud run services update-traffic "$service" --region "$region" --to-latest --quiet
gcloud run services describe "$service" --region "$region" --format='value(status.url)'
