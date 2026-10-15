# One Google service account per workload, used from its Kubernetes service
# account through Workload Identity. No keys exist anywhere.

locals {
  workloads = {
    ingest = {
      ksa   = "ingest"
      roles = ["roles/cloudsql.client", "roles/cloudsql.instanceUser"]
    }
    search = {
      ksa   = "search"
      roles = ["roles/cloudsql.client", "roles/cloudsql.instanceUser"]
    }
    # Logs in as the built-in admin user (password from Secret Manager) to run
    # migrations and grant the IAM users their roles.
    migrate = {
      ksa   = "migrate"
      roles = ["roles/cloudsql.client"]
    }
  }

  workload_roles = merge([
    for name, w in local.workloads : { for r in w.roles : "${name}/${r}" => { name = name, role = r } }
  ]...)
}

resource "google_service_account" "workload" {
  for_each     = local.workloads
  account_id   = "${var.name}-${each.key}"
  display_name = "Lecture Indexer ${each.key} workload"
}

resource "google_project_iam_member" "workload" {
  for_each = local.workload_roles
  project  = var.gcp_project_id
  role     = each.value.role
  member   = google_service_account.workload[each.value.name].member
}

resource "google_service_account_iam_member" "workload_identity" {
  for_each           = local.workloads
  service_account_id = google_service_account.workload[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${module.gke.workload_pool}[${var.k8s_namespace}/${each.value.ksa}]"
  # The identity pool only exists once the cluster does.
  depends_on = [module.gke]
}
