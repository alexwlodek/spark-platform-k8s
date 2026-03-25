module "gke" {
  source = "../../../modules/gke"

  project_id                    = var.project_id
  region                        = var.region
  zones                         = var.zones
  cluster_name                  = var.cluster_name
  network_name                  = var.network_name
  subnetwork_name               = var.subnetwork_name
  pods_secondary_range_name     = var.pods_secondary_range_name
  services_secondary_range_name = var.services_secondary_range_name
  master_ipv4_cidr_block        = var.master_ipv4_cidr_block
  master_authorized_networks    = var.master_authorized_networks
  node_service_account_name     = var.node_service_account_name
  external_secrets_gsa_name     = var.external_secrets_gsa_name
  platform_machine_type         = var.platform_machine_type
  platform_disk_size_gb         = var.platform_disk_size_gb
  platform_disk_type            = var.platform_disk_type
  bootstrap_disk_size_gb        = var.bootstrap_disk_size_gb
  bootstrap_disk_type           = var.bootstrap_disk_type
  platform_total_min_nodes      = var.platform_total_min_nodes
  platform_total_max_nodes      = var.platform_total_max_nodes
  labels                        = var.labels
}
