terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
    time = {
      source = "hashicorp/time"
    }
  }
}

variable "cluster_name" { type = string }
variable "project" { type = string }
variable "aws_region" { type = string }
variable "cluster_endpoint" { type = string }
variable "cluster_ca_certificate" { type = string }
variable "oidc_provider_arn" { type = string }
variable "oidc_provider_url" { type = string }
variable "cluster_security_group_id" { type = string }

variable "rds_endpoint" { type = string }
variable "redis_endpoint" { type = string }
variable "s3_evidence_bucket" { type = string }
variable "s3_models_bucket" { type = string }
variable "app_s3_role_arn" { type = string }

variable "postgres_password" {
  type      = string
  sensitive = true
}
variable "redis_password" {
  type      = string
  sensitive = true
}
variable "rabbitmq_password" {
  type      = string
  sensitive = true
}
variable "jwt_secret_key" {
  type      = string
  sensitive = true
}

variable "argocd_admin_password" {
  type      = string
  sensitive = true
}

variable "fabric_security_group_id" { type = string }
variable "fabric_anchor_url" { type = string }

variable "route53_zone_id" { type = string }
variable "domain_name" { type = string }
variable "argocd_domain" { type = string }
variable "acm_certificate_arn" { type = string }
variable "acm_certificate_arn_argocd" { type = string }

variable "alb_controller_role_arn" { type = string }
variable "install_alb_controller" {
  type    = bool
  default = true
}

variable "argocd_repo_url" { type = string }
variable "argocd_target_revision" { type = string }
variable "argocd_app_path" { type = string }

variable "wake_automation_enabled" {
  type    = bool
  default = true
}

variable "wake_trigger" {
  type        = string
  description = "Wake provisioner 재실행 트리거 (wake_run_id 또는 cluster id)"
}

variable "fabric_health_url" {
  type    = string
  default = "http://10.0.10.224:8088/health"
}

variable "app_health_url" {
  type    = string
  default = ""
}

locals {
  oidc_host = replace(var.oidc_provider_url, "https://", "")
}
