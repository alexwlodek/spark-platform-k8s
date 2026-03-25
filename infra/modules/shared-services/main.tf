locals {
  common_labels = merge(
    {
      environment = var.environment
      platform    = "data-platform"
      managed_by  = "terraform"
      stack       = "shared-services"
    },
    var.labels
  )
}

resource "google_project_service" "sqladmin" {
  project            = var.project_id
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

data "google_compute_network" "main" {
  name = var.network_name
}

resource "google_storage_bucket" "lake" {
  name                        = var.lake_bucket_name
  location                    = var.lake_bucket_location
  force_destroy               = var.lake_bucket_force_destroy
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = local.common_labels

  versioning {
    enabled = true
  }
}

resource "google_service_account" "lake_runtime" {
  account_id   = var.lake_runtime_gsa_name
  display_name = "${var.environment} lake runtime"
}

resource "google_storage_bucket_iam_member" "lake_runtime_object_admin" {
  bucket = google_storage_bucket.lake.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.lake_runtime.email}"
}

resource "google_service_account_iam_member" "lake_runtime_spark_workload_identity" {
  service_account_id = google_service_account.lake_runtime.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.apps_namespace}/${var.spark_service_account_name}]"
}

resource "google_service_account_iam_member" "lake_runtime_trino_workload_identity" {
  service_account_id = google_service_account.lake_runtime.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.apps_namespace}/${var.trino_service_account_name}]"
}

resource "google_service_account" "nessie_runtime" {
  account_id   = var.nessie_runtime_gsa_name
  display_name = "${var.environment} nessie runtime"
}

resource "google_project_iam_member" "nessie_runtime_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.nessie_runtime.email}"
}

resource "google_service_account_iam_member" "nessie_runtime_workload_identity" {
  service_account_id = google_service_account.nessie_runtime.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.apps_namespace}/${var.nessie_service_account_name}]"
}

resource "random_password" "nessie_db_password" {
  length  = 32
  special = false
}

resource "google_sql_database_instance" "nessie" {
  name                = var.cloud_sql_instance_name
  database_version    = var.cloud_sql_database_version
  region              = var.region
  deletion_protection = var.cloud_sql_deletion_protection

  settings {
    edition           = var.cloud_sql_edition
    tier              = var.cloud_sql_tier
    availability_type = var.cloud_sql_availability_type
    disk_type         = var.cloud_sql_disk_type
    disk_size         = var.cloud_sql_disk_size_gb
    disk_autoresize   = true

    backup_configuration {
      enabled                        = true
      start_time                     = var.cloud_sql_backup_start_time
      point_in_time_recovery_enabled = var.cloud_sql_enable_point_in_time_recovery
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.main.id
      enable_private_path_for_google_cloud_services = true
    }

    user_labels = local.common_labels
  }

  depends_on = [google_project_service.sqladmin]
}

resource "google_sql_database" "nessie" {
  name     = var.cloud_sql_database_name
  instance = google_sql_database_instance.nessie.name
}

resource "google_sql_user" "nessie" {
  name     = var.cloud_sql_user_name
  instance = google_sql_database_instance.nessie.name
  password = random_password.nessie_db_password.result
}

resource "google_secret_manager_secret" "nessie_credentials" {
  secret_id = var.nessie_secret_id
  labels    = local.common_labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "nessie_credentials" {
  secret = google_secret_manager_secret.nessie_credentials.id
  secret_data = jsonencode({
    "db-username" = google_sql_user.nessie.name
    "db-password" = random_password.nessie_db_password.result
  })
}
