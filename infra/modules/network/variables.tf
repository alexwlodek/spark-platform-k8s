variable "project_id" {
  description = "GCP project ID used for the production network."
  type        = string
}

variable "region" {
  description = "Regional location used for the production network."
  type        = string
}

variable "network_name" {
  description = "VPC network name."
  type        = string
}

variable "subnetwork_name" {
  description = "Subnetwork name for the GKE cluster."
  type        = string
}

variable "subnet_cidr" {
  description = "Primary subnet CIDR for GKE nodes."
  type        = string
}

variable "pods_secondary_range_name" {
  description = "Secondary range name used for GKE pods."
  type        = string
}

variable "pods_cidr" {
  description = "Secondary CIDR used for GKE pods."
  type        = string
}

variable "services_secondary_range_name" {
  description = "Secondary range name used for GKE services."
  type        = string
}

variable "services_cidr" {
  description = "Secondary CIDR used for GKE services."
  type        = string
}

variable "base_domain" {
  description = "Base domain delegated to Cloudflare."
  type        = string
}

variable "environment_subdomain" {
  description = "Environment subdomain inserted before the base domain."
  type        = string
}

variable "public_hostnames" {
  description = "Host labels published behind the shared public gateway."
  type        = list(string)
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID used for public DNS records. Leave empty to skip DNS management."
  type        = string
}

variable "public_gateway_ip_name" {
  description = "Reserved global IP name used by the shared public gateway."
  type        = string
}

variable "cloud_sql_private_service_range_name" {
  description = "Reserved private service range name used for Cloud SQL private IP."
  type        = string
}

variable "cloud_sql_private_service_range_prefix_length" {
  description = "Prefix length for the private service range used by Cloud SQL private IP."
  type        = number
}
