variable "project_id" {
  description = "GCP project ID used for production managed platform services."
  type        = string
}

variable "region" {
  description = "Regional location used for production managed platform services."
  type        = string
}

variable "environment" {
  description = "Environment label applied to managed platform services."
  type        = string
}

variable "network_name" {
  description = "Existing VPC network name created by the network stack."
  type        = string
}

variable "apps_namespace" {
  description = "Kubernetes namespace used by runtime applications."
  type        = string
}

variable "lake_bucket_name" {
  description = "Primary Cloud Storage bucket used by the data lake workloads."
  type        = string
}

variable "lake_bucket_location" {
  description = "Location for the primary Cloud Storage bucket."
  type        = string
}

variable "lake_bucket_force_destroy" {
  description = "Whether Terraform should delete the lake bucket even when it contains objects."
  type        = bool
}

variable "lake_runtime_gsa_name" {
  description = "Service account ID used by Spark and Trino for GCS access."
  type        = string
}

variable "nessie_runtime_gsa_name" {
  description = "Service account ID used by Nessie for Cloud SQL access."
  type        = string
}

variable "spark_service_account_name" {
  description = "Kubernetes service account name used by Spark jobs."
  type        = string
}

variable "trino_service_account_name" {
  description = "Kubernetes service account name used by Trino."
  type        = string
}

variable "nessie_service_account_name" {
  description = "Kubernetes service account name used by Nessie."
  type        = string
}

variable "cloud_sql_instance_name" {
  description = "Cloud SQL instance name used for Nessie metadata."
  type        = string
}

variable "cloud_sql_database_version" {
  description = "Cloud SQL database engine version."
  type        = string
}

variable "cloud_sql_edition" {
  description = "Cloud SQL edition. Use ENTERPRISE for custom db-custom tiers, or ENTERPRISE_PLUS with predefined db-perf-optimized-* tiers."
  type        = string

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.cloud_sql_edition)
    error_message = "cloud_sql_edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "cloud_sql_tier" {
  description = "Cloud SQL machine tier for the Nessie metadata database."
  type        = string
}

variable "cloud_sql_availability_type" {
  description = "Cloud SQL availability type."
  type        = string
}

variable "cloud_sql_disk_type" {
  description = "Cloud SQL disk type."
  type        = string
}

variable "cloud_sql_disk_size_gb" {
  description = "Initial Cloud SQL disk size in GB."
  type        = number
}

variable "cloud_sql_backup_start_time" {
  description = "UTC backup start time for Cloud SQL."
  type        = string
}

variable "cloud_sql_enable_point_in_time_recovery" {
  description = "Whether point-in-time recovery is enabled for Cloud SQL backups."
  type        = bool
}

variable "cloud_sql_deletion_protection" {
  description = "Whether Terraform should enable Cloud SQL deletion protection."
  type        = bool
}

variable "cloud_sql_database_name" {
  description = "Database name used by Nessie."
  type        = string
}

variable "cloud_sql_user_name" {
  description = "Database user used by Nessie."
  type        = string
}

variable "nessie_secret_id" {
  description = "Secret Manager secret ID containing Nessie database credentials."
  type        = string
}

variable "labels" {
  description = "Additional labels applied to supported resources."
  type        = map(string)
}
