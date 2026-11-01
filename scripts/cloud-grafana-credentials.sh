#!/usr/bin/env bash
# Create or rotate the read-only credentials Grafana Cloud uses, and store them in
# its data sources (docs/monitoring/grafana-cloud-plan.md). They're made here so
# that they never land in Terraform state. Running this again replaces both.
#   GRAFANA_URL=https://<stack>.grafana.net GRAFANA_AUTH=<token> make cloud-grafana-credentials
# Needs az and gcloud (signed in with access to both identities), curl and jq, and
# infra/terraform/bootstrap applied first.
set -euo pipefail

PROJECT=${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}
IDENTITY=li-grafana

[[ -n $PROJECT ]] || { echo "No GCP project: set GCP_PROJECT or run gcloud config set project." >&2; exit 1; }
: "${GRAFANA_URL:?Set GRAFANA_URL to the stack URL, https://<stack>.grafana.net}"
: "${GRAFANA_AUTH:?Set GRAFANA_AUTH to a Grafana service account token}"
GRAFANA_URL=${GRAFANA_URL%/}

email=$IDENTITY@$PROJECT.iam.gserviceaccount.com
# --show-mine: an earlier app of this name with no owner is still in the directory.
client_id=$(az ad app list --show-mine --query "[?displayName=='$IDENTITY'] | [0].appId" --output tsv)
[[ -n $client_id ]] || { echo "You don't own a $IDENTITY app in Azure: apply infra/terraform/bootstrap first." >&2; exit 1; }

key_file=$(mktemp)
trap 'shred -u "$key_file"' EXIT

# The token goes through a file descriptor and the body through stdin, not the
# arguments, so neither can show up in a process list.
grafana() {  # grafana <method> <path> [curl arguments]
  local method=$1 path=$2
  shift 2
  curl --config <(printf 'header = "Authorization: Bearer %s"\n' "$GRAFANA_AUTH") \
    --silent --show-error --request "$method" "$GRAFANA_URL$path" "$@"
}

# Fixed UIDs, because the dashboard refers to its data sources by UID.
save_data_source() {  # save_data_source <uid>, with the JSON on stdin
  local uid=$1 status
  status=$(grafana GET "/api/datasources/uid/$uid" --output /dev/null --write-out '%{http_code}')
  case $status in
    200) grafana PUT "/api/datasources/uid/$uid" --fail --output /dev/null \
           --header 'Content-Type: application/json' --data-binary @- ;;
    404) grafana POST /api/datasources --fail --output /dev/null \
           --header 'Content-Type: application/json' --data-binary @- ;;
    *) echo "Grafana answered $status for data source $uid." >&2; exit 1 ;;
  esac
}

gcloud iam service-accounts keys create "$key_file" --iam-account "$email" --project "$PROJECT" --quiet
jq --null-input --slurpfile key "$key_file" '{
  uid: "li-gcp", name: "Google Cloud Monitoring", type: "stackdriver", access: "proxy",
  jsonData: {
    authenticationType: "jwt",
    clientEmail: $key[0].client_email,
    defaultProject: $key[0].project_id,
    tokenUri: $key[0].token_uri
  },
  secureJsonData: { privateKey: $key[0].private_key }
}' | save_data_source li-gcp

# Grafana has the new key, so the old ones can go.
new_key=$(jq --raw-output .private_key_id "$key_file")
for key in $(gcloud iam service-accounts keys list --iam-account "$email" --project "$PROJECT" \
    --managed-by user --format='value(name.basename())'); do
  [[ $key == "$new_key" ]] || gcloud iam service-accounts keys delete "$key" --iam-account "$email" \
    --project "$PROJECT" --quiet
done

# In the environment, not an argument, so the secret can't show up in a process list.
# This replaces the app's existing secret. A new one can take a minute to work.
CLIENT_SECRET=$(az ad app credential reset --id "$client_id" --years 1 --query password --output tsv 2>/dev/null)
export CLIENT_SECRET

expiry=$(date -u -d '+1 year' +%Y-%m-%d)
jq --null-input --arg client_id "$client_id" \
  --arg tenant "$(az account show --query tenantId --output tsv)" \
  --arg subscription "$(az account show --query id --output tsv)" '{
  uid: "li-azure", name: "Azure Monitor", type: "grafana-azure-monitor-datasource", access: "proxy",
  jsonData: {
    azureAuthType: "clientsecret",
    cloudName: "azuremonitor",
    clientId: $client_id,
    tenantId: $tenant,
    subscriptionId: $subscription
  },
  secureJsonData: { clientSecret: env.CLIENT_SECRET }
}' | save_data_source li-azure

echo "Stored new credentials in Grafana. The Azure secret expires on $expiry: renew it before then."
