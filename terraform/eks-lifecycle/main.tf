module "bootstrap" {
  source = "./modules/bootstrap"
  count  = var.eks_enabled && var.bootstrap_enabled ? 1 : 0

  cluster_name = var.cluster_name
  project      = var.project
  aws_region   = var.aws_region

  cluster_endpoint       = aws_eks_cluster.this[0].endpoint
  cluster_ca_certificate = aws_eks_cluster.this[0].certificate_authority[0].data
  oidc_provider_arn      = aws_iam_openid_connect_provider.eks[0].arn
  oidc_provider_url      = aws_eks_cluster.this[0].identity[0].oidc[0].issuer

  cluster_security_group_id = aws_eks_cluster.this[0].vpc_config[0].cluster_security_group_id

  rds_endpoint       = var.rds_endpoint
  redis_endpoint     = var.redis_endpoint
  s3_evidence_bucket = var.s3_evidence_bucket
  s3_models_bucket   = var.s3_models_bucket
  app_s3_role_arn    = var.app_s3_role_arn

  postgres_password = var.postgres_password
  redis_password    = var.redis_password
  rabbitmq_password = var.rabbitmq_password
  jwt_secret_key    = var.jwt_secret_key
  argocd_admin_password = var.argocd_admin_password

  fabric_security_group_id = var.fabric_security_group_id
  fabric_anchor_url        = var.fabric_anchor_url

  route53_zone_id            = var.route53_zone_id
  domain_name                = var.domain_name
  argocd_domain              = var.argocd_domain
  acm_certificate_arn        = var.acm_certificate_arn
  acm_certificate_arn_argocd = var.acm_certificate_arn_argocd

  alb_controller_role_arn = var.alb_controller_role_arn
  install_alb_controller  = var.install_alb_controller

  argocd_repo_url        = var.argocd_repo_url
  argocd_target_revision = var.argocd_target_revision
  argocd_app_path        = var.argocd_app_path

  wake_automation_enabled = var.wake_automation_enabled
  wake_trigger            = local.wake_trigger
  fabric_health_url       = var.fabric_health_url
  app_health_url          = var.app_health_url

  depends_on = [
    aws_eks_node_group.frontend,
    aws_eks_node_group.backend,
    aws_eks_node_group.ai_fastapi,
    aws_eks_addon.coredns,
    terraform_data.wake_rds_start,
    terraform_data.wake_fabric_ec2_start,
    terraform_data.wake_fabric_sg_rule,
  ]
}
