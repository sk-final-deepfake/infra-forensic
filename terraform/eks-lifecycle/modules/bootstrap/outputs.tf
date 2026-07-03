output "app_alb_dns" {
  value = var.domain_name
}

output "argocd_alb_dns" {
  value = var.argocd_domain
}

output "fabric_sg_rule_id" {
  value = "script-managed"
}

output "wake_verification_complete" {
  value       = try(terraform_data.verify_app_health[0].id, null)
  description = "Pod wait + HTTPS health check 완료 시 설정됨"
}
