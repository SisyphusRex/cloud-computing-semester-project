#!/usr/bin/env bash
# Pause the deployed environment between test sessions, and resume it.
#   make cloud-status | cloud-pause | cloud-resume   (or scripts/cloud-power.sh <command>)
#
# pause:  scale ingest and search to 0, delete the Ingress (the load balancer),
#         stop Cloud SQL. Cluster, data, images and the reserved IP stay, so the
#         API hostname doesn't change.
# resume: start Cloud SQL, scale back to 1 (the HPAs take over), re-create the
#         Ingress from the prod overlay.
#
# Needs gcloud, kubectl and gke-gcloud-auth-plugin (install steps:
# docs/local-development.md#install-cloud-tools-optional). DRY_RUN=1 prints
# the commands without running them, and doesn't need the tools.
# See docs/runbooks/bootstrap.md, "Control cost".
set -euo pipefail

case ${1:-} in
  pause | resume | status) ;;
  *) echo "usage: $0 pause|resume|status" >&2; exit 2 ;;
esac

# Check every tool before changing anything, so a missing one can't leave the
# environment half paused.
if [[ ${DRY_RUN:-0} != 1 ]]; then
  missing=()
  for tool in gcloud kubectl gke-gcloud-auth-plugin; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  if (( ${#missing[@]} )); then
    echo "Missing: ${missing[*]}" >&2
    echo "Install steps: docs/local-development.md#install-cloud-tools-optional (or use Cloud Shell)" >&2
    exit 1
  fi
fi

PROJECT=${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}
REGION=${GCP_REGION:-us-central1}
CLUSTER=${GKE_CLUSTER:-li}
SQL_INSTANCE=${SQL_INSTANCE:-li-pg}
NAMESPACE=${K8S_NAMESPACE:-li}
OVERLAY=deploy/k8s/overlays/prod
DEPLOYMENTS=(deploy/ingest deploy/search)
CONTEXT="gke_${PROJECT}_${REGION}_${CLUSTER}"

run() {
  echo "+ $*"
  [[ ${DRY_RUN:-0} == 1 ]] || "$@"
}

kube() { run kubectl --context "$CONTEXT" -n "$NAMESPACE" "$@"; }

# Adds or refreshes the cluster's kubeconfig entry; every kubectl call names
# the context explicitly, so the current context doesn't matter.
connect() {
  run gcloud container clusters get-credentials "$CLUSTER" \
    --region "$REGION" --project "$PROJECT" --quiet
}

app_deployed() {
  [[ ${DRY_RUN:-0} == 1 ]] && return 0
  kubectl --context "$CONTEXT" get namespace "$NAMESPACE" >/dev/null 2>&1
}

sql() { run gcloud sql instances patch "$SQL_INSTANCE" --project "$PROJECT" --quiet "$@"; }

# Progress: "==> [2/4] Delete the load balancer (expected: 1-5 min)", then how
# long the step actually took, and the total at the end.
STEP=0
STEPS=0
STEP_START=$SECONDS
duration() { printf '%dm%02ds' $(($1 / 60)) $(($1 % 60)); }
end_step() {
  if ((STEP > 0)); then echo "    done in $(duration $((SECONDS - STEP_START)))"; fi
}
step() {  # step <description> <expected wait>
  end_step
  STEP=$((STEP + 1))
  STEP_START=$SECONDS
  echo
  echo "==> [$STEP/$STEPS] $1 (expected: $2)"
}
finish() {  # finish <message...>
  end_step
  echo
  echo "Finished in $(duration "$SECONDS")."
  printf '%s\n' "$@"
}

# The release and rollback workflows skip while this annotation is set
# (scripts/ci/check-paused.sh). Set first on pause and removed last on resume,
# so a half-finished pause or resume still counts as paused.
PAUSED_ANNOTATION=lecture-indexer/paused

pause() {
  STEPS=4
  echo "Pausing $PROJECT: usually 3-8 minutes."
  step "Connect to the cluster" "seconds"
  connect
  if app_deployed; then
    step "Mark the environment paused, scale ingest and search to 0" "seconds"
    run kubectl --context "$CONTEXT" annotate namespace "$NAMESPACE" "$PAUSED_ANNOTATION=true" --overwrite
    kube scale "${DEPLOYMENTS[@]}" --replicas=0
    step "Delete the Ingress; waits until GKE has removed the load balancer" "1-5 min"
    kube delete ingress li-api --ignore-not-found
  else
    echo "Namespace $NAMESPACE not found; skipping the Kubernetes steps."
    STEP=3
  fi
  step "Stop Cloud SQL $SQL_INSTANCE; waits for the stop to finish" "1-3 min"
  sql --activation-policy=NEVER
  finish "Paused. Cloud SQL storage and the reserved IP are still billed (a few dollars a month)." \
    "Check with: make cloud-status"
}

resume() {
  STEPS=5
  echo "Resuming $PROJECT: usually 5-10 minutes here, then 5-10 more until the load balancer serves traffic."
  step "Start Cloud SQL $SQL_INSTANCE; waits until it's running" "2-5 min"
  sql --activation-policy=ALWAYS
  step "Connect to the cluster" "seconds"
  connect
  if app_deployed; then
    step "Scale ingest and search to 1, re-create the Ingress" "seconds"
    kube scale "${DEPLOYMENTS[@]}" --replicas=1
    # Apply only the Ingress: re-applying the whole overlay would reset the
    # image tags to the ones committed in kustomization.yaml.
    echo "+ kubectl kustomize $OVERLAY | kubectl apply -l app.kubernetes.io/component=ingress -f -"
    if [[ ${DRY_RUN:-0} != 1 ]]; then
      kubectl kustomize "$OVERLAY" |
        kubectl --context "$CONTEXT" apply -l app.kubernetes.io/component=ingress -f -
    fi
    step "Wait for the pods; Autopilot may start a new Spot node first" "2-4 min"
    for d in "${DEPLOYMENTS[@]}"; do kube rollout status "$d" --timeout=5m; done
    step "Clear the paused mark (releases can run again)" "seconds"
    run kubectl --context "$CONTEXT" annotate namespace "$NAMESPACE" "$PAUSED_ANNOTATION-"
    finish "Resumed. The load balancer needs 5-10 more minutes before the API answers;" \
      "the frontend shows API errors until then. Check with: make cloud-status" \
      "If a release skipped while paused: GitHub → Actions → Release → Run workflow (main)," \
      "  or: gh workflow run release.yml --ref main"
  else
    finish "Cloud SQL is running, but namespace $NAMESPACE doesn't exist yet: run a release first."
  fi
}

status() {
  echo "Cloud SQL $SQL_INSTANCE (policy, state):"
  gcloud sql instances describe "$SQL_INSTANCE" --project "$PROJECT" \
    --format='value(settings.activationPolicy,state)'
  connect >/dev/null
  if app_deployed; then
    echo "Deployments:"
    kubectl --context "$CONTEXT" -n "$NAMESPACE" get "${DEPLOYMENTS[@]}"
    echo "Ingress:"
    kubectl --context "$CONTEXT" -n "$NAMESPACE" get ingress li-api 2>/dev/null || echo "  none (no load balancer)"
  else
    echo "Namespace $NAMESPACE not found."
  fi
  echo "Global forwarding rules (billed per rule):"
  gcloud compute forwarding-rules list --global --project "$PROJECT" --format='value(name)'
}

[[ -n $PROJECT ]] || { echo "No GCP project: set GCP_PROJECT or run gcloud config set project." >&2; exit 1; }
"$1"
