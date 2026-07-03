resource "aws_eks_node_group" "frontend" {
  count = var.eks_enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.this[0].name
  node_group_name = "frontend-ng"
  node_role_arn   = var.eks_node_role_arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = var.frontend_desired
    min_size     = var.frontend_desired > 0 ? 1 : 0
    max_size     = 2
  }

  labels = {
    nodegroup = "frontend-ng"
  }

  tags = {
    "eks.amazonaws.com/nodegroup" = "frontend-ng"
  }

  depends_on = [aws_eks_cluster.this]
}

resource "aws_eks_node_group" "backend" {
  count = var.eks_enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.this[0].name
  node_group_name = "backend-ng"
  node_role_arn   = var.eks_node_role_arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = var.backend_desired
    min_size     = var.backend_desired > 0 ? 1 : 0
    max_size     = 4
  }

  labels = {
    nodegroup = "backend-ng"
  }

  tags = {
    "eks.amazonaws.com/nodegroup" = "backend-ng"
  }

  depends_on = [aws_eks_cluster.this]
}

resource "aws_eks_node_group" "ai_fastapi" {
  count = var.eks_enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.this[0].name
  node_group_name = "ai-fastapi-ng"
  node_role_arn   = var.eks_node_role_arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = var.ai_fastapi_desired
    min_size     = var.ai_fastapi_desired > 0 ? 1 : 0
    max_size     = 2
  }

  labels = {
    nodegroup = "ai-fastapi-ng"
  }

  tags = {
    "eks.amazonaws.com/nodegroup" = "ai-fastapi-ng"
  }

  depends_on = [aws_eks_cluster.this]
}
