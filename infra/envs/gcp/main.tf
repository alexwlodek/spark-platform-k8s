locals {
  common_labels = merge(
    {
      environment = "prod"
      platform    = "data-platform"
      cluster     = var.cluster_name
      managed_by  = "terraform"
    },
    var.labels
  )
}

resource "google_compute_network" "main" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "gke" {
  name                     = var.subnetwork_name
  region                   = var.region
  network                  = google_compute_network.main.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = var.pods_secondary_range_name
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = var.services_secondary_range_name
    ip_cidr_range = var.services_cidr
  }
}

resource "google_compute_router" "nat" {
  name    = "${var.cluster_name}-nat-router"
  region  = var.region
  network = google_compute_network.main.name
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.cluster_name}-nat"
  region                             = var.region
  router                             = google_compute_router.nat.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.gke.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

resource "google_service_account" "nodes" {
  account_id   = var.node_service_account_name
  display_name = "${var.cluster_name} GKE nodes"
}

resource "google_service_account" "external_secrets" {
  account_id   = var.external_secrets_gsa_name
  display_name = "${var.cluster_name} external-secrets"
}

resource "google_project_iam_member" "nodes_default_role" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_project_iam_member" "external_secrets_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.external_secrets.email}"
}

resource "google_service_account_iam_member" "external_secrets_workload_identity" {
  service_account_id = google_service_account.external_secrets.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets]"

  depends_on = [google_container_cluster.prod]
}

resource "google_container_cluster" "prod" {
  name                = var.cluster_name
  location            = var.region
  network             = google_compute_network.main.id
  subnetwork          = google_compute_subnetwork.gke.name
  node_locations      = var.zones
  deletion_protection = false

  remove_default_node_pool = true
  initial_node_count       = 1

  node_config {
    disk_size_gb    = var.bootstrap_disk_size_gb
    disk_type       = var.bootstrap_disk_type
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  resource_labels = local.common_labels

  depends_on = [
    google_compute_router_nat.nat,
    google_project_iam_member.nodes_default_role,
  ]
}

resource "google_container_node_pool" "platform" {
  name           = "platform"
  cluster        = google_container_cluster.prod.name
  location       = var.region
  node_locations = var.zones

  initial_node_count = 1

  autoscaling {
    total_min_node_count = var.platform_total_min_nodes
    total_max_node_count = var.platform_total_max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.platform_machine_type
    disk_size_gb    = var.platform_disk_size_gb
    disk_type       = var.platform_disk_type
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = {
      nodepool = "platform"
      workload = "platform"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  depends_on = [
    google_project_iam_member.nodes_default_role,
    google_compute_router_nat.nat,
  ]
}

resource "google_compute_global_address" "argocd" {
  name = "argocd-prod-ip"
}
