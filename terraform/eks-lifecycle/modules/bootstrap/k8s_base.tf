resource "kubernetes_namespace_v1" "forenshield" {
  metadata {
    name = "forenshield"
    labels = {
      project = var.project
    }
  }
}

resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type = "gp3"
  }
}

resource "kubernetes_config_map_v1" "app_config" {
  metadata {
    name      = "app-config"
    namespace = kubernetes_namespace_v1.forenshield.metadata[0].name
  }
  data = {
    AWS_REGION                   = var.aws_region
    RABBITMQ_HOST                = "rabbitmq.forenshield.svc.cluster.local"
    RABBITMQ_PORT                = "5672"
    AI_GATEWAY_URL               = "http://192.168.0.66:8000"
    SPRING_PROFILES_ACTIVE       = "prod"
    SPRING_JPA_HIBERNATE_DDL_AUTO = "update"
    SERVER_PORT                  = "8080"
    REDIS_PORT                   = "6379"
    REDIS_SSL                    = "true"
    ANALYSIS_WORKER_MODE         = "ai"
    BLOCKCHAIN_ANCHOR_ENABLED    = "true"
    BLOCKCHAIN_ANCHOR_MODE       = "http"
    BLOCKCHAIN_ANCHOR_URL        = var.fabric_anchor_url
    BLOCKCHAIN_ANCHOR_NETWORK    = "hyperledger-fabric-forenshield"
  }
}

resource "kubernetes_config_map_v1" "frontend_config" {
  metadata {
    name      = "frontend-config"
    namespace = kubernetes_namespace_v1.forenshield.metadata[0].name
  }
  data = {
    NEXT_PUBLIC_API_URL = "https://${var.domain_name}"
  }
}

resource "kubernetes_secret_v1" "db_credentials" {
  metadata {
    name      = "db-credentials"
    namespace = kubernetes_namespace_v1.forenshield.metadata[0].name
  }
  data = {
    POSTGRES_HOST     = var.rds_endpoint
    POSTGRES_USER     = "forenshield"
    POSTGRES_PASSWORD = var.postgres_password
    POSTGRES_DB       = "forenshield"
  }
  type = "Opaque"
}

resource "kubernetes_secret_v1" "redis_credentials" {
  metadata {
    name      = "redis-credentials"
    namespace = kubernetes_namespace_v1.forenshield.metadata[0].name
  }
  data = {
    REDIS_HOST     = var.redis_endpoint
    REDIS_PASSWORD = var.redis_password
  }
  type = "Opaque"
}

resource "kubernetes_secret_v1" "rabbitmq_credentials" {
  metadata {
    name      = "rabbitmq-credentials"
    namespace = kubernetes_namespace_v1.forenshield.metadata[0].name
  }
  data = {
    RABBITMQ_HOST     = "rabbitmq.forenshield.svc.cluster.local"
    RABBITMQ_PORT     = "5672"
    RABBITMQ_USER     = "forenshield"
    RABBITMQ_PASSWORD = var.rabbitmq_password
  }
  type = "Opaque"
}

resource "kubernetes_secret_v1" "app_secrets" {
  metadata {
    name      = "app-secrets"
    namespace = kubernetes_namespace_v1.forenshield.metadata[0].name
  }
  # JWT + Manifest 서명 PEM — deployment envFrom: app-secrets 만으로 주입 (별도 manifest-signing-credentials 불필요)
  data = merge(
    {
      JWT_SECRET_KEY = var.jwt_secret_key
    },
    var.manifest_signing_private_key_pem != "" && var.manifest_signing_certificate_pem != "" ? {
      MANIFEST_SIGNING_PRIVATE_KEY_PEM  = var.manifest_signing_private_key_pem
      MANIFEST_SIGNING_CERTIFICATE_PEM  = var.manifest_signing_certificate_pem
    } : {}
  )
  type = "Opaque"
}

resource "kubernetes_secret_v1" "s3_config" {
  metadata {
    name      = "s3-config"
    namespace = kubernetes_namespace_v1.forenshield.metadata[0].name
  }
  data = {
    AWS_ROLE_ARN         = var.app_s3_role_arn
    S3_EVIDENCE_BUCKET   = var.s3_evidence_bucket
    S3_MODELS_BUCKET     = var.s3_models_bucket
  }
  type = "Opaque"
}

resource "kubernetes_service_account_v1" "app" {
  metadata {
    name      = "forenshield-app"
    namespace = kubernetes_namespace_v1.forenshield.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = var.app_s3_role_arn
    }
  }
}
