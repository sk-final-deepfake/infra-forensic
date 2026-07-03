resource "helm_release" "alb_controller" {
  count = var.install_alb_controller ? 1 : 0

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.2"
  wait       = true
  timeout    = 600

  set {
    name  = "clusterName"
    value = var.cluster_name
  }
  set {
    name  = "region"
    value = var.aws_region
  }
  set {
    name  = "vpcId"
    value = data.aws_eks_cluster.this.vpc_config[0].vpc_id
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.alb_controller_role_arn
  }
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

resource "time_sleep" "wait_for_alb_webhook" {
  count           = var.install_alb_controller ? 1 : 0
  create_duration = "120s"
  depends_on      = [helm_release.alb_controller]
}

resource "helm_release" "rabbitmq" {
  name       = "rabbitmq"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "rabbitmq"
  namespace  = kubernetes_namespace_v1.forenshield.metadata[0].name
  version    = "14.6.9"

  values = [yamlencode({
    global = {
      security = {
        allowInsecureImages = true
      }
    }
    image = {
      repository = "bitnamilegacy/rabbitmq"
    }
    volumePermissions = {
      image = {
        repository = "bitnamilegacy/os-shell"
      }
    }
    auth = {
      username = "forenshield"
      password = var.rabbitmq_password
    }
    persistence = {
      enabled      = true
      size         = "10Gi"
      storageClass = kubernetes_storage_class_v1.gp3.metadata[0].name
    }
    nodeSelector = {
      "eks.amazonaws.com/nodegroup" = "backend-ng"
    }
    service = {
      type = "ClusterIP"
    }
    metrics = {
      enabled = true
    }
    replicaCount = 1
  })]

  depends_on = [
    kubernetes_storage_class_v1.gp3,
    time_sleep.wait_for_alb_webhook,
  ]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  version          = "7.3.11"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    server = {
      service = { type = "ClusterIP" }
      ingress = { enabled = false }
    }
    configs = {
      cm = {
        url = "https://${var.argocd_domain}"
      }
      secret = {
        # Helm chart expects bcrypt hash, not plaintext (argo-helm values.yaml)
        argocdServerAdminPassword = bcrypt(var.argocd_admin_password, 10)
      }
      params = {
        "server.insecure" = true
      }
    }
  })]

  depends_on = [
    kubernetes_namespace_v1.forenshield,
    time_sleep.wait_for_alb_webhook,
  ]
}
