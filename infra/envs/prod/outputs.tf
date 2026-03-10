output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_oidc_provider_arn" {
  description = "OIDC provider ARN used by IRSA roles."
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "VPC ID for production cluster."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by worker nodes."
  value       = module.vpc.private_subnets
}

output "aws_load_balancer_controller_irsa_role_arn" {
  description = "IRSA role ARN for aws-load-balancer-controller."
  value       = module.irsa_aws_load_balancer_controller.arn
}

output "external_secrets_irsa_role_arn" {
  description = "IRSA role ARN to configure in values/prod/external-secrets.yaml."
  value       = module.irsa_external_secrets.arn
}

output "ebs_csi_irsa_role_arn" {
  description = "IRSA role ARN for aws-ebs-csi-driver addon."
  value       = module.irsa_ebs_csi.arn
}

output "external_secrets_secret_prefix" {
  description = "Secrets Manager prefix readable by external-secrets."
  value       = var.external_secrets_secret_prefix
}

output "argocd_hostname" {
  description = "Expected public hostname for Argo CD ingress."
  value       = var.argocd_hostname
}

output "configure_kubectl_command" {
  description = "Command to configure kubectl context for production EKS."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name} --alias ${module.eks.cluster_name}"
}
