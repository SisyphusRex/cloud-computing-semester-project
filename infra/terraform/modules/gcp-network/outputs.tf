output "network_id" {
  value = google_compute_network.this.id
}

output "subnet_id" {
  value = google_compute_subnetwork.gke.id
}

output "pods_range_name" {
  value = "pods"
}

output "services_range_name" {
  value = "services"
}

output "private_services_connection" {
  description = "Depend on this before creating private-IP Cloud SQL."
  value       = google_service_networking_connection.private_services.id
}
