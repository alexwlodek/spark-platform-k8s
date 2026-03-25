module "network" {
  source = "../../../modules/network"

  project_id                                    = var.project_id
  region                                        = var.region
  network_name                                  = var.network_name
  subnetwork_name                               = var.subnetwork_name
  subnet_cidr                                   = var.subnet_cidr
  pods_secondary_range_name                     = var.pods_secondary_range_name
  pods_cidr                                     = var.pods_cidr
  services_secondary_range_name                 = var.services_secondary_range_name
  services_cidr                                 = var.services_cidr
  base_domain                                   = var.base_domain
  environment_subdomain                         = var.environment_subdomain
  public_hostnames                              = var.public_hostnames
  cloudflare_zone_id                            = var.cloudflare_zone_id
  public_gateway_ip_name                        = var.public_gateway_ip_name
  cloud_sql_private_service_range_name          = var.cloud_sql_private_service_range_name
  cloud_sql_private_service_range_prefix_length = var.cloud_sql_private_service_range_prefix_length
}
