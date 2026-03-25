output "project_id" {
  description = "GCP project ID used by the managed platform services stack."
  value       = var.project_id
}

output "lake_bucket_name" {
  description = "Primary Cloud Storage bucket name used by the data lake workloads."
  value       = google_storage_bucket.lake.name
}

output "lake_runtime_gsa_email" {
  description = "Service account mapped to Spark and Trino workloads for GCS access."
  value       = google_service_account.lake_runtime.email
}

output "nessie_runtime_gsa_email" {
  description = "Service account mapped to Nessie for Cloud SQL access."
  value       = google_service_account.nessie_runtime.email
}

output "cloud_sql_instance_name" {
  description = "Cloud SQL instance name used for Nessie metadata."
  value       = google_sql_database_instance.nessie.name
}

output "cloud_sql_instance_connection_name" {
  description = "Cloud SQL connection name for proxy-based access from GKE."
  value       = google_sql_database_instance.nessie.connection_name
}

output "cloud_sql_private_ip_address" {
  description = "Private IP address assigned to the Cloud SQL instance."
  value       = google_sql_database_instance.nessie.private_ip_address
}

output "cloud_sql_database_name" {
  description = "Nessie database name."
  value       = google_sql_database.nessie.name
}

output "cloud_sql_user_name" {
  description = "Nessie database user."
  value       = google_sql_user.nessie.name
}

output "nessie_secret_id" {
  description = "Secret Manager secret ID containing Nessie database credentials."
  value       = google_secret_manager_secret.nessie_credentials.secret_id
}
