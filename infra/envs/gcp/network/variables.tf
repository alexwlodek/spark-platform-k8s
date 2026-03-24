variable "project_id" {
  description = "GCP project ID used for the production network."
  type        = string
  default     = "data-platform-prod-491113"
}

variable "region" {
  description = "Regional location used for the production network."
  type        = string
  default     = "europe-central2"
}

variable "network_name" {
  description = "VPC network name."
  type        = string
  default     = "data-platform-prod-vpc"
}

variable "subnetwork_name" {
  description = "Subnetwork name for the GKE cluster."
  type        = string
  default     = "data-platform-prod-gke"
}

variable "subnet_cidr" {
  description = "Primary subnet CIDR for GKE nodes."
  type        = string
  default     = "10.70.0.0/20"
}

variable "pods_secondary_range_name" {
  description = "Secondary range name used for GKE pods."
  type        = string
  default     = "gke-pods"
}

variable "pods_cidr" {
  description = "Secondary CIDR used for GKE pods."
  type        = string
  default     = "10.80.0.0/14"
}

variable "services_secondary_range_name" {
  description = "Secondary range name used for GKE services."
  type        = string
  default     = "gke-services"
}

variable "services_cidr" {
  description = "Secondary CIDR used for GKE services."
  type        = string
  default     = "10.84.0.0/20"
}

variable "base_domain" {
  description = "Base domain delegated to Cloudflare."
  type        = string
  default     = "alexwlodek.com"
}

variable "environment_subdomain" {
  description = "Environment subdomain inserted before the base domain."
  type        = string
  default     = "prod"
}

variable "public_hostnames" {
  description = "Host labels published behind the shared public gateway."
  type        = list(string)
  default = [
    "argocd",
    "grafana",
    "kibana",
  ]
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID used for public DNS records. Leave empty to skip DNS management."
  type        = string
  default     = ""
}

variable "public_gateway_ip_name" {
  description = "Reserved global IP name used by the shared public gateway."
  type        = string
  default     = "data-platform-prod-public-gateway-ip"
}
