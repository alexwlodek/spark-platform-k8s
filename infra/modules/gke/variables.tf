variable "project_id" {
  description = "GCP project ID used for the production GKE cluster."
  type        = string
}

variable "region" {
  description = "Regional location for the production GKE cluster."
  type        = string
}

variable "zones" {
  description = "Zones used by the regional platform node pool."
  type        = list(string)
}

variable "cluster_name" {
  description = "Production GKE cluster name."
  type        = string
}

variable "network_name" {
  description = "Existing VPC network name created by the network stack."
  type        = string
}

variable "subnetwork_name" {
  description = "Existing subnetwork name created by the network stack."
  type        = string
}

variable "pods_secondary_range_name" {
  description = "Secondary range name used for GKE pods."
  type        = string
}

variable "services_secondary_range_name" {
  description = "Secondary range name used for GKE services."
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "Control plane CIDR for the private GKE cluster."
  type        = string
}

variable "master_authorized_networks" {
  description = "CIDR blocks allowed to reach the public control plane endpoint."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
}

variable "node_service_account_name" {
  description = "Service account ID used by GKE nodes."
  type        = string
}

variable "external_secrets_gsa_name" {
  description = "Service account ID used by External Secrets on GKE."
  type        = string
}

variable "platform_machine_type" {
  description = "Machine type for the platform node pool."
  type        = string
}

variable "platform_disk_size_gb" {
  description = "Disk size for platform nodes."
  type        = number
}

variable "platform_disk_type" {
  description = "Disk type for platform nodes."
  type        = string
}

variable "bootstrap_disk_size_gb" {
  description = "Disk size for the temporary default node pool created during cluster bootstrap."
  type        = number
}

variable "bootstrap_disk_type" {
  description = "Disk type for the temporary default node pool created during cluster bootstrap."
  type        = string
}

variable "platform_total_min_nodes" {
  description = "Minimum total nodes for the regional platform node pool."
  type        = number
}

variable "platform_total_max_nodes" {
  description = "Maximum total nodes for the regional platform node pool."
  type        = number
}

variable "labels" {
  description = "Additional labels applied to supported resources."
  type        = map(string)
}
