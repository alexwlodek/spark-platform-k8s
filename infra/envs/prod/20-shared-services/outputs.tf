output "project_id" {
  description = "GCP project ID used by the managed platform services stack."
  value       = module.shared_services.project_id
}

output "lake_bucket_name" {
  description = "Primary Cloud Storage bucket name used by the data lake workloads."
  value       = module.shared_services.lake_bucket_name
}

output "lake_runtime_gsa_email" {
  description = "Service account mapped to Spark and Trino workloads for GCS access."
  value       = module.shared_services.lake_runtime_gsa_email
}

output "nessie_runtime_gsa_email" {
  description = "Service account mapped to Nessie for Cloud SQL access."
  value       = module.shared_services.nessie_runtime_gsa_email
}

output "cloud_sql_instance_name" {
  description = "Cloud SQL instance name used for Nessie metadata."
  value       = module.shared_services.cloud_sql_instance_name
}

output "cloud_sql_instance_connection_name" {
  description = "Cloud SQL connection name for proxy-based access from GKE."
  value       = module.shared_services.cloud_sql_instance_connection_name
}

output "cloud_sql_private_ip_address" {
  description = "Private IP address assigned to the Cloud SQL instance."
  value       = module.shared_services.cloud_sql_private_ip_address
}

output "cloud_sql_database_name" {
  description = "Nessie database name."
  value       = module.shared_services.cloud_sql_database_name
}

output "cloud_sql_user_name" {
  description = "Nessie database user."
  value       = module.shared_services.cloud_sql_user_name
}

output "nessie_secret_id" {
  description = "Secret Manager secret ID containing Nessie database credentials."
  value       = module.shared_services.nessie_secret_id
}
