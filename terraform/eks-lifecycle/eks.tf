resource "aws_eks_cluster" "this" {
  count = var.eks_enabled ? 1 : 0

  name     = var.cluster_name
  role_arn = var.eks_cluster_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.cluster_subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = {
    Name = var.cluster_name
  }
}

locals {
  cluster_name = var.eks_enabled ? aws_eks_cluster.this[0].name : var.cluster_name
}

resource "aws_eks_addon" "vpc_cni" {
  count = var.eks_enabled ? 1 : 0

  cluster_name                = aws_eks_cluster.this[0].name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.backend]
}

resource "aws_eks_addon" "kube_proxy" {
  count = var.eks_enabled ? 1 : 0

  cluster_name                = aws_eks_cluster.this[0].name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.backend]
}

resource "aws_eks_addon" "coredns" {
  count = var.eks_enabled ? 1 : 0

  cluster_name                = aws_eks_cluster.this[0].name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.backend]
}
