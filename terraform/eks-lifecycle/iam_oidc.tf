data "tls_certificate" "eks" {
  count = var.eks_enabled ? 1 : 0
  url   = aws_eks_cluster.this[0].identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  count = var.eks_enabled ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks[0].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this[0].identity[0].oidc[0].issuer
}

resource "aws_eks_addon" "ebs_csi" {
  count = var.eks_enabled && var.install_ebs_csi ? 1 : 0

  cluster_name                = aws_eks_cluster.this[0].name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = var.ebs_csi_role_arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  timeouts {
    create = "30m"
    update = "30m"
  }

  depends_on = [
    aws_eks_node_group.backend,
    aws_iam_openid_connect_provider.eks,
  ]
}
