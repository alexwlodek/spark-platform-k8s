variable "aws_region" {
  description = "AWS region for production infrastructure."
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "data-platform-prod"
}

variable "cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.34"
}

variable "vpc_cidr" {
  description = "CIDR range for the production VPC."
  type        = string
  default     = "10.70.0.0/16"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR ranges allowed to access the public EKS API endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_group_instance_types" {
  description = "Instance types for the default EKS managed node group."
  type        = list(string)
  default     = ["m6i.large"]
}

variable "node_group_desired_size" {
  description = "Desired number of nodes in the default node group."
  type        = number
  default     = 3
}

variable "node_group_min_size" {
  description = "Minimum number of nodes in the default node group."
  type        = number
  default     = 3
}

variable "node_group_max_size" {
  description = "Maximum number of nodes in the default node group."
  type        = number
  default     = 6
}

variable "node_group_disk_size" {
  description = "Root EBS volume size (GiB) for worker nodes."
  type        = number
  default     = 120
}

variable "aws_load_balancer_controller_chart_version" {
  description = "Helm chart version for aws-load-balancer-controller."
  type        = string
  default     = "1.8.1"
}

variable "ebs_csi_addon_version" {
  description = "Optional explicit aws-ebs-csi-driver addon version. Empty means AWS default."
  type        = string
  default     = ""
}

variable "argocd_hostname" {
  description = "Public DNS host used by Argo CD ingress in production."
  type        = string
  default     = "argocd.prod.example.com"
}

variable "external_secrets_namespace" {
  description = "Namespace where external-secrets controller runs."
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_service_account_name" {
  description = "ServiceAccount name used by external-secrets for IRSA auth."
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_secret_prefix" {
  description = "Secrets Manager prefix readable by external-secrets."
  type        = string
  default     = "/spark-platform/prod/"
}

variable "tags" {
  description = "Additional tags applied to AWS resources."
  type        = map(string)
  default     = {}
}
