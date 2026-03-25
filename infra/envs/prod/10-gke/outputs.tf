output "project_id" {
  description = "GCP project ID used by the platform."
  value       = module.gke.project_id
}

output "cluster_name" {
  description = "Production GKE cluster name."
  value       = module.gke.cluster_name
}

output "cluster_region" {
  description = "Regional location of the production GKE cluster."
  value       = module.gke.cluster_region
}

output "network_name" {
  description = "VPC used by the production GKE cluster."
  value       = module.gke.network_name
}

output "subnetwork_name" {
  description = "Subnetwork used by the production GKE cluster."
  value       = module.gke.subnetwork_name
}

output "node_service_account_email" {
  description = "Service account attached to the GKE node pool."
  value       = module.gke.node_service_account_email
}

output "external_secrets_gsa_email" {
  description = "Service account mapped to the external-secrets Kubernetes service account."
  value       = module.gke.external_secrets_gsa_email
}

output "get_credentials_command" {
  description = "Command to configure kubectl for the new GKE cluster."
  value       = module.gke.get_credentials_command
}
