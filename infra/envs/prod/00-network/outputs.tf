output "project_id" {
  description = "GCP project ID used by the platform."
  value       = module.network.project_id
}

output "region" {
  description = "Region used by the production network."
  value       = module.network.region
}

output "network_name" {
  description = "VPC used by the production GKE cluster."
  value       = module.network.network_name
}

output "subnetwork_name" {
  description = "Subnetwork used by the production GKE cluster."
  value       = module.network.subnetwork_name
}

output "pods_secondary_range_name" {
  description = "Secondary range name used by GKE pods."
  value       = module.network.pods_secondary_range_name
}

output "services_secondary_range_name" {
  description = "Secondary range name used by GKE services."
  value       = module.network.services_secondary_range_name
}

output "public_gateway_ip_name" {
  description = "Global static IP name referenced by the shared public gateway."
  value       = module.network.public_gateway_ip_name
}

output "public_gateway_ip_address" {
  description = "Global static IP address reserved for the shared public gateway."
  value       = module.network.public_gateway_ip_address
}

output "cloud_sql_private_service_range_name" {
  description = "Private service range reserved for Cloud SQL private IP."
  value       = module.network.cloud_sql_private_service_range_name
}

output "public_hosts" {
  description = "Expected public hosts routed by the shared public gateway."
  value       = module.network.public_hosts
}
