resource "terraform_data" "wait_k8s_workloads" {
  count = var.wake_automation_enabled ? 1 : 0

  triggers_replace = [var.wake_trigger]

  provisioner "local-exec" {
    command     = "powershell -ExecutionPolicy Bypass -File ${path.root}/scripts/wait-k8s-ready.ps1 -ClusterName ${var.cluster_name} -Region ${var.aws_region} -FabricHealthUrl ${var.fabric_health_url}"
    working_dir = path.root
  }

  depends_on = [
    helm_release.rabbitmq,
    helm_release.argocd,
    terraform_data.argocd_app,
    terraform_data.route53_upsert,
  ]
}

resource "time_sleep" "wait_for_dns" {
  count = var.wake_automation_enabled ? 1 : 0

  create_duration = "60s"

  depends_on = [
    terraform_data.route53_upsert,
    terraform_data.wait_k8s_workloads,
  ]
}

resource "terraform_data" "verify_app_health" {
  count = var.wake_automation_enabled && var.app_health_url != "" ? 1 : 0

  triggers_replace = [var.wake_trigger]

  provisioner "local-exec" {
    command     = "powershell -ExecutionPolicy Bypass -File ${path.root}/scripts/verify-app-health.ps1 -Url ${var.app_health_url}"
    working_dir = path.root
  }

  depends_on = [time_sleep.wait_for_dns]
}
