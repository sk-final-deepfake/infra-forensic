resource "terraform_data" "route53_upsert" {
  triggers_replace = [
    var.domain_name,
    var.argocd_domain,
    var.route53_zone_id,
  ]

  provisioner "local-exec" {
    command     = "powershell -ExecutionPolicy Bypass -File ${path.root}/scripts/upsert-route53.ps1 -ClusterName ${var.cluster_name} -Region ${var.aws_region} -ZoneId ${var.route53_zone_id} -AppDomain ${var.domain_name} -ArgocdDomain ${var.argocd_domain}"
    working_dir = path.root
  }

  depends_on = [
    kubernetes_ingress_v1.app,
    kubernetes_ingress_v1.argocd,
  ]
}
