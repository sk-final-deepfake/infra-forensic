data "aws_eks_cluster" "this" {
  count = var.eks_enabled ? 1 : 0
  name  = var.cluster_name

  depends_on = [aws_eks_cluster.this]
}

data "aws_eks_cluster_auth" "this" {
  count = var.eks_enabled ? 1 : 0
  name  = var.cluster_name

  depends_on = [aws_eks_cluster.this]
}

provider "kubernetes" {
  host                   = var.eks_enabled ? coalesce(try(aws_eks_cluster.this[0].endpoint, null), try(data.aws_eks_cluster.this[0].endpoint, null), "https://kubernetes.default.svc") : "https://kubernetes.default.svc"
  cluster_ca_certificate = var.eks_enabled ? coalesce(try(base64decode(aws_eks_cluster.this[0].certificate_authority[0].data), null), try(base64decode(data.aws_eks_cluster.this[0].certificate_authority[0].data), null), "") : ""
  token                  = var.eks_enabled ? try(data.aws_eks_cluster_auth.this[0].token, "") : ""
}

provider "helm" {
  kubernetes {
    host                   = var.eks_enabled ? coalesce(try(aws_eks_cluster.this[0].endpoint, null), try(data.aws_eks_cluster.this[0].endpoint, null), "https://kubernetes.default.svc") : "https://kubernetes.default.svc"
    cluster_ca_certificate = var.eks_enabled ? coalesce(try(base64decode(aws_eks_cluster.this[0].certificate_authority[0].data), null), try(base64decode(data.aws_eks_cluster.this[0].certificate_authority[0].data), null), "") : ""
    token                  = var.eks_enabled ? try(data.aws_eks_cluster_auth.this[0].token, "") : ""
  }
}
