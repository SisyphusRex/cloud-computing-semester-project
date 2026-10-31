# Secret Manager secrets, each readable only by the members listed for it.
# Values are passed separately because they are ephemeral.

resource "google_secret_manager_secret" "this" {
  for_each  = var.secrets
  secret_id = each.key
  labels    = var.labels

  replication {
    auto {}
  }
}

# Write-only: values never land in Terraform state, and refreshes don't read
# them back, so a plan needs no access to secret data.
resource "google_secret_manager_secret_version" "this" {
  for_each               = var.secrets
  secret                 = google_secret_manager_secret.this[each.key].id
  secret_data_wo         = var.secret_values[each.key]
  secret_data_wo_version = lookup(var.secret_value_versions, each.key, 1)
}

resource "google_secret_manager_secret_iam_member" "accessors" {
  for_each = merge([
    for id, s in var.secrets : {
      for name, m in s.accessors : "${id}/${name}" => { id = id, member = m }
    }
  ]...)
  secret_id = google_secret_manager_secret.this[each.value.id].id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}
