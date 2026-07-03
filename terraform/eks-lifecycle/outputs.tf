output "eks_enabled" {
  value = var.eks_enabled
}

output "cluster_name" {
  value = local.cluster_name
}

output "cluster_endpoint" {
  value       = var.eks_enabled ? aws_eks_cluster.this[0].endpoint : null
  description = "kubeconfig 갱신 후 kubectl 사용"
}

output "cluster_security_group_id" {
  value       = var.eks_enabled ? aws_eks_cluster.this[0].vpc_config[0].cluster_security_group_id : null
  description = "Fabric EC2 SG 인바운드 8088 규칙 대상 — Terraform bootstrap이 자동 갱신"
}

output "oidc_provider_arn" {
  value = var.eks_enabled ? aws_iam_openid_connect_provider.eks[0].arn : null
}

output "oidc_provider_url" {
  value = var.eks_enabled ? aws_eks_cluster.this[0].identity[0].oidc[0].issuer : null
}

output "cluster_arn" {
  value = var.eks_enabled ? aws_eks_cluster.this[0].arn : null
}

output "bootstrap_app_alb_dns" {
  value = try(module.bootstrap[0].app_alb_dns, null)
}

output "bootstrap_argocd_alb_dns" {
  value = try(module.bootstrap[0].argocd_alb_dns, null)
}

output "wake_verification_complete" {
  value       = try(module.bootstrap[0].wake_verification_complete, null)
  description = "Wake 자동 검증(Pod+HTTPS) 완료"
}
