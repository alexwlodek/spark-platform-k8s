output "project_id" {
  description = "GCP project ID used by the platform."
  value       = var.project_id
}

output "region" {
  description = "Region used by the production network."
  value       = var.region
}

output "network_name" {
  description = "VPC used by the production GKE cluster."
  value       = google_compute_network.main.name
}

output "subnetwork_name" {
  description = "Subnetwork used by the production GKE cluster."
  value       = google_compute_subnetwork.gke.name
}

output "pods_secondary_range_name" {
  description = "Secondary range name used by GKE pods."
  value       = var.pods_secondary_range_name
}

output "services_secondary_range_name" {
  description = "Secondary range name used by GKE services."
  value       = var.services_secondary_range_name
}

output "public_gateway_ip_name" {
  description = "Global static IP name referenced by the shared public gateway."
  value       = google_compute_global_address.public_gateway.name
}

output "public_gateway_ip_address" {
  description = "Global static IP address reserved for the shared public gateway."
  value       = google_compute_global_address.public_gateway.address
}

output "cloud_sql_private_service_range_name" {
  description = "Private service range reserved for Cloud SQL private IP."
  value       = google_compute_global_address.cloud_sql_private_service_range.name
}

output "public_hosts" {
  description = "Expected public hosts routed by the shared public gateway."
  value       = local.public_hosts
}
