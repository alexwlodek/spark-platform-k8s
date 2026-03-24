variable "project_id" {
  description = "GCP project ID used for the production GKE cluster."
  type        = string
  default     = "data-platform-prod-491113"
}

variable "region" {
  description = "Regional location for the production GKE cluster."
  type        = string
  default     = "europe-central2"
}

variable "zones" {
  description = "Zones used by the regional platform node pool."
  type        = list(string)
  default = [
    "europe-central2-a",
    "europe-central2-b",
    "europe-central2-c",
  ]
}

variable "cluster_name" {
  description = "Production GKE cluster name."
  type        = string
  default     = "data-platform-prod"
}

variable "network_name" {
  description = "Existing VPC network name created by the network stack."
  type        = string
  default     = "data-platform-prod-vpc"
}

variable "subnetwork_name" {
  description = "Existing subnetwork name created by the network stack."
  type        = string
  default     = "data-platform-prod-gke"
}

variable "pods_secondary_range_name" {
  description = "Secondary range name used for GKE pods."
  type        = string
  default     = "gke-pods"
}

variable "services_secondary_range_name" {
  description = "Secondary range name used for GKE services."
  type        = string
  default     = "gke-services"
}

variable "master_ipv4_cidr_block" {
  description = "Control plane CIDR for the private GKE cluster."
  type        = string
  default     = "172.16.0.0/28"
}

variable "master_authorized_networks" {
  description = "CIDR blocks allowed to reach the public control plane endpoint."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "node_service_account_name" {
  description = "Service account ID used by GKE nodes."
  type        = string
  default     = "gke-nodes"
}

variable "external_secrets_gsa_name" {
  description = "Service account ID used by External Secrets on GKE."
  type        = string
  default     = "external-secrets"
}

variable "platform_machine_type" {
  description = "Machine type for the platform node pool."
  type        = string
  default     = "e2-standard-2"
}

variable "platform_disk_size_gb" {
  description = "Disk size for platform nodes."
  type        = number
  default     = 50
}

variable "platform_disk_type" {
  description = "Disk type for platform nodes."
  type        = string
  default     = "pd-standard"
}

variable "bootstrap_disk_size_gb" {
  description = "Disk size for the temporary default node pool created during cluster bootstrap."
  type        = number
  default     = 20
}

variable "bootstrap_disk_type" {
  description = "Disk type for the temporary default node pool created during cluster bootstrap."
  type        = string
  default     = "pd-standard"
}

variable "platform_total_min_nodes" {
  description = "Minimum total nodes for the regional platform node pool."
  type        = number
  default     = 3
}

variable "platform_total_max_nodes" {
  description = "Maximum total nodes for the regional platform node pool."
  type        = number
  default     = 6
}

variable "labels" {
  description = "Additional labels applied to supported resources."
  type        = map(string)
  default     = {}
}
