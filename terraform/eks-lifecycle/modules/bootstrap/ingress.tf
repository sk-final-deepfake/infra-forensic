resource "kubernetes_ingress_v1" "app" {
  metadata {
    name      = "forenshield-ingress"
    namespace = kubernetes_namespace_v1.forenshield.metadata[0].name
    annotations = {
      "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"        = "ip"
      "alb.ingress.kubernetes.io/listen-ports"         = jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
      "alb.ingress.kubernetes.io/ssl-redirect"         = "443"
      "alb.ingress.kubernetes.io/certificate-arn"      = var.acm_certificate_arn
      "alb.ingress.kubernetes.io/load-balancer-name"   = "forenshield-k8s-app"
    }
  }

  spec {
    ingress_class_name = "alb"
    rule {
      host = var.domain_name
      http {
        path {
          path      = "/api"
          path_type = "Prefix"
          backend {
            service {
              name = "backend"
              port { number = 8080 }
            }
          }
        }
        path {
          path      = "/actuator"
          path_type = "Prefix"
          backend {
            service {
              name = "backend"
              port { number = 8080 }
            }
          }
        }
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "frontend"
              port { number = 80 }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.alb_controller, time_sleep.wait_for_alb_webhook]

  timeouts {
    delete = "3m"
  }
}

resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-ingress"
    namespace = "argocd"
    annotations = {
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"        = "ip"
      "alb.ingress.kubernetes.io/listen-ports"         = jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
      "alb.ingress.kubernetes.io/ssl-redirect"         = "443"
      "alb.ingress.kubernetes.io/certificate-arn"      = var.acm_certificate_arn_argocd
      "alb.ingress.kubernetes.io/healthcheck-path"   = "/healthz"
      "alb.ingress.kubernetes.io/load-balancer-name" = "forenshield-k8s-argocd"
    }
  }

  spec {
    ingress_class_name = "alb"
    rule {
      host = var.argocd_domain
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port { number = 80 }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.argocd]

  timeouts {
    delete = "3m"
  }
}

resource "time_sleep" "wait_for_argocd_crds" {
  create_duration = "90s"
  depends_on      = [helm_release.argocd]
}
