output "project_id" {
  description = "GCP project ID used by the platform."
  value       = var.project_id
}

output "cluster_name" {
  description = "Production GKE cluster name."
  value       = google_container_cluster.prod.name
}

output "cluster_region" {
  description = "Regional location of the production GKE cluster."
  value       = google_container_cluster.prod.location
}

output "network_name" {
  description = "VPC used by the production GKE cluster."
  value       = google_compute_network.main.name
}

output "subnetwork_name" {
  description = "Subnetwork used by the production GKE cluster."
  value       = google_compute_subnetwork.gke.name
}

output "node_service_account_email" {
  description = "Service account attached to the GKE node pool."
  value       = google_service_account.nodes.email
}

output "external_secrets_gsa_email" {
  description = "Service account mapped to the external-secrets Kubernetes service account."
  value       = google_service_account.external_secrets.email
}

output "argocd_static_ip_name" {
  description = "Global static IP name referenced by the Argo CD ingress."
  value       = google_compute_global_address.argocd.name
}

output "argocd_static_ip_address" {
  description = "Global static IP address reserved for Argo CD."
  value       = google_compute_global_address.argocd.address
}

output "argocd_hostname" {
  description = "Expected public hostname for the Argo CD ingress."
  value       = var.argocd_hostname
}

output "get_credentials_command" {
  description = "Command to configure kubectl for the new GKE cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.prod.name} --region ${var.region} --project ${var.project_id}"
}
