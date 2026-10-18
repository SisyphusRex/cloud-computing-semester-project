#!/usr/bin/env bash
# Used by the deploy workflows: is the environment paused (make cloud-pause)?
#   scripts/ci/check-paused.sh sql          Cloud SQL only (terraform.yml)
#   scripts/ci/check-paused.sh sql+k8s      also the Ingress (services-deploy.yml)
# Writes paused=true|false to $GITHUB_OUTPUT and, when paused, a warning and a
# job summary saying how to resume and re-run. Needs gcloud (and kubectl with a
# current context for sql+k8s).
set -euo pipefail

SQL_INSTANCE=${SQL_INSTANCE:-li-pg}
NAMESPACE=${K8S_NAMESPACE:-li}
reasons=()

# Before the first apply there's no instance, so nothing is paused. Any other
# gcloud error (permissions, API) fails the step instead of guessing.
if [[ -n $(gcloud sql instances list --filter="name=$SQL_INSTANCE" --format='value(name)') ]]; then
  info=$(gcloud sql instances describe "$SQL_INSTANCE" --format='value(settings.activationPolicy,state)')
  read -r activation state <<< "$info"
  if [[ $activation != ALWAYS || $state != RUNNABLE ]]; then
    reasons+=("Cloud SQL $SQL_INSTANCE is $activation/$state")
  fi
fi

# cloud-pause deletes the Ingress. Applying the app overlay now would re-create
# it (and the load balancer's cost) while the pods stay at 0. A missing
# namespace means the first deploy, which is not a pause.
if [[ ${1:-} == sql+k8s ]] && kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
  if ! kubectl -n "$NAMESPACE" get ingress li-api > /dev/null 2>&1; then
    reasons+=("Ingress li-api is missing")
  fi
fi

if (( ${#reasons[@]} == 0 )); then
  echo "paused=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

workflow=${GITHUB_WORKFLOW_REF%%@*} # owner/repo/.github/workflows/<file>@<ref>
workflow=${workflow##*/}
echo "paused=true" >> "$GITHUB_OUTPUT"
joined=$(IFS=';'; echo "${reasons[*]}")
echo "::warning title=Environment is paused::${joined//;/; }. Skipped; after make cloud-resume, re-run this workflow."
{
  echo "### Skipped: the environment is paused"
  printf -- '- %s\n' "${reasons[@]}"
  echo
  echo "Run \`make cloud-resume\`, then re-run this workflow:"
  echo "\`gh workflow run $workflow --ref main\`"
} >> "$GITHUB_STEP_SUMMARY"
