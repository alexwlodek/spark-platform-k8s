locals {
  public_hosts = {
    for host in var.public_hostnames :
    host => "${host}.${var.environment_subdomain}.${var.base_domain}"
  }
}

resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_compute_network" "main" {
  name                    = var.network_name
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
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
  name    = "${var.environment_subdomain}-gke-nat-router"
  region  = var.region
  network = google_compute_network.main.name
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.environment_subdomain}-gke-nat"
  region                             = var.region
  router                             = google_compute_router.nat.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.gke.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

resource "google_compute_global_address" "public_gateway" {
  name         = var.public_gateway_ip_name
  address_type = "EXTERNAL"
  ip_version   = "IPV4"

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.compute]
}

resource "cloudflare_dns_record" "public_hosts" {
  for_each = var.cloudflare_zone_id == "" ? {} : local.public_hosts

  zone_id = var.cloudflare_zone_id
  name    = each.value
  content = google_compute_global_address.public_gateway.address
  type    = "A"
  ttl     = 1
  proxied = false
  comment = "Shared production public gateway"
}
