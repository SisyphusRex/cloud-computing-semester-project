output "name" {
  value = google_container_cluster.this.name
}

output "location" {
  value = google_container_cluster.this.location
}

output "workload_pool" {
  description = "Workload Identity pool, e.g. <project>.svc.id.goog."
  value       = "${var.project_id}.svc.id.goog"
}

output "node_service_account" {
  value = google_service_account.nodes.email
}
