variable "project_id" {
  description = "GCP project ID used for production managed platform services."
  type        = string
  default     = "data-platform-prod-491113"
}

variable "region" {
  description = "Regional location used for production managed platform services."
  type        = string
  default     = "europe-central2"
}

variable "environment" {
  description = "Environment label applied to managed platform services."
  type        = string
  default     = "prod"
}

variable "network_name" {
  description = "Existing VPC network name created by the network stack."
  type        = string
  default     = "data-platform-prod-vpc"
}

variable "apps_namespace" {
  description = "Kubernetes namespace used by runtime applications."
  type        = string
  default     = "apps"
}

variable "lake_bucket_name" {
  description = "Primary Cloud Storage bucket used by the data lake workloads."
  type        = string
  default     = "data-platform-prod-lake"
}

variable "lake_bucket_location" {
  description = "Location for the primary Cloud Storage bucket."
  type        = string
  default     = "EUROPE-CENTRAL2"
}

variable "lake_runtime_gsa_name" {
  description = "Service account ID used by Spark and Trino for GCS access."
  type        = string
  default     = "lake-runtime"
}

variable "nessie_runtime_gsa_name" {
  description = "Service account ID used by Nessie for Cloud SQL access."
  type        = string
  default     = "nessie-runtime"
}

variable "spark_service_account_name" {
  description = "Kubernetes service account name used by Spark jobs."
  type        = string
  default     = "spark-operator-spark"
}

variable "trino_service_account_name" {
  description = "Kubernetes service account name used by Trino."
  type        = string
  default     = "bi-trino"
}

variable "nessie_service_account_name" {
  description = "Kubernetes service account name used by Nessie."
  type        = string
  default     = "storage-nessie"
}

variable "cloud_sql_instance_name" {
  description = "Cloud SQL instance name used for Nessie metadata."
  type        = string
  default     = "data-platform-prod-nessie"
}

variable "cloud_sql_database_version" {
  description = "Cloud SQL database engine version."
  type        = string
  default     = "POSTGRES_16"
}

variable "cloud_sql_tier" {
  description = "Cloud SQL machine tier for the Nessie metadata database."
  type        = string
  default     = "db-custom-1-3840"
}

variable "cloud_sql_availability_type" {
  description = "Cloud SQL availability type."
  type        = string
  default     = "ZONAL"
}

variable "cloud_sql_disk_type" {
  description = "Cloud SQL disk type."
  type        = string
  default     = "PD_SSD"
}

variable "cloud_sql_disk_size_gb" {
  description = "Initial Cloud SQL disk size in GB."
  type        = number
  default     = 20
}

variable "cloud_sql_backup_start_time" {
  description = "UTC backup start time for Cloud SQL."
  type        = string
  default     = "03:00"
}

variable "cloud_sql_enable_point_in_time_recovery" {
  description = "Whether point-in-time recovery is enabled for Cloud SQL backups."
  type        = bool
  default     = true
}

variable "cloud_sql_deletion_protection" {
  description = "Whether Terraform should enable Cloud SQL deletion protection."
  type        = bool
  default     = false
}

variable "cloud_sql_database_name" {
  description = "Database name used by Nessie."
  type        = string
  default     = "nessie"
}

variable "cloud_sql_user_name" {
  description = "Database user used by Nessie."
  type        = string
  default     = "nessie"
}

variable "nessie_secret_id" {
  description = "Secret Manager secret ID containing Nessie database credentials."
  type        = string
  default     = "spark-platform-prod-storage-nessie"
}

variable "labels" {
  description = "Additional labels applied to supported resources."
  type        = map(string)
  default     = {}
}
