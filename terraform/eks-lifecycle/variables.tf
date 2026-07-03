variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "project" {
  type    = string
  default = "forenshield"
}

variable "cluster_name" {
  type    = string
  default = "forenshield"
}

variable "kubernetes_version" {
  type    = string
  default = "1.36"
}

# false → EKS 클러스터 + 노드그룹 전부 삭제 (Control Plane 과금 중단)
variable "eks_enabled" {
  type        = bool
  default     = true
  description = "false면 EKS Control Plane·Node Group 삭제. VPC/RDS/S3는 유지."
}

# 기존 CLI로 만든 VPC/서브넷 ID — terraform.tfvars에 채움
variable "private_subnet_ids" {
  type        = list(string)
  description = "EKS worker용 Private subnet 2개"
}

variable "cluster_subnet_ids" {
  type        = list(string)
  description = "Control plane ENI용 — 보통 private + public subnet 4개"
}

variable "eks_cluster_role_arn" {
  type        = string
  description = "forenshield-eks-cluster-role ARN"
}

variable "eks_node_role_arn" {
  type        = string
  description = "forenshield-eks-node-role ARN"
}

variable "frontend_desired" {
  type    = number
  default = 1
}

variable "backend_desired" {
  type    = number
  default = 2
}

variable "ai_fastapi_desired" {
  type    = number
  default = 1
}

variable "bootstrap_enabled" {
  type        = bool
  default     = true
  description = "EKS 생성 시 K8s Secret/Helm/Argo/Route53/Fabric SG 자동 적용"
}

variable "postgres_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "redis_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "rabbitmq_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "jwt_secret_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "argocd_admin_password" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Argo CD admin 계정 비밀번호 (Helm configs.secret.argocdServerAdminPassword)"
}

variable "rds_endpoint" {
  type    = string
  default = ""
}

variable "redis_endpoint" {
  type    = string
  default = ""
}

variable "s3_evidence_bucket" {
  type    = string
  default = ""
}

variable "s3_models_bucket" {
  type    = string
  default = ""
}

variable "app_s3_role_arn" {
  type    = string
  default = ""
}

variable "install_ebs_csi" {
  type        = bool
  default     = true
  description = "false면 Phase1에서 EBS CSI 제외 (trust patch 후 true)"
}

variable "ebs_csi_role_arn" {
  type        = string
  default     = "arn:aws:iam::877044078824:role/forenshield-ebs-csi-role"
  description = "EBS CSI driver IRSA role"
}

variable "fabric_security_group_id" {
  type    = string
  default = ""
}

variable "fabric_anchor_url" {
  type    = string
  default = ""
}

variable "route53_zone_id" {
  type    = string
  default = ""
}

variable "domain_name" {
  type    = string
  default = "forensheildjangdochi.com"
}

variable "argocd_domain" {
  type    = string
  default = "argocd.forensheildjangdochi.com"
}

variable "acm_certificate_arn" {
  type    = string
  default = ""
}

variable "acm_certificate_arn_argocd" {
  type    = string
  default = ""
}

variable "alb_controller_role_arn" {
  type    = string
  default = ""
}

variable "install_alb_controller" {
  type    = bool
  default = true
}

variable "argocd_repo_url" {
  type    = string
  default = "https://github.com/sk-final-deepfake/infra-forensic.git"
}

variable "argocd_target_revision" {
  type    = string
  default = "master"
}

variable "argocd_app_path" {
  type    = string
  default = "config/k8s"
}

variable "rds_instance_identifier" {
  type        = string
  default     = "forenshield-db"
  description = "Wake 시 start / Park 시 stop 대상 RDS"
}

variable "fabric_instance_id" {
  type        = string
  default     = "i-08f10733c96e387fc"
  description = "Fabric PoC EC2 — Wake 시 start+Gateway / Park 시 stop"
}

variable "fabric_health_url" {
  type    = string
  default = "http://10.0.10.224:8088/health"
}

variable "app_health_url" {
  type    = string
  default = "https://forensheildjangdochi.com/health"
}

variable "wake_automation_enabled" {
  type        = bool
  default     = true
  description = "RDS/EC2 start, Pod wait, HTTPS health check 자동화"
}

variable "park_automation_enabled" {
  type        = bool
  default     = true
  description = "Park 시 RDS/EC2 stop 자동화"
}

variable "wake_run_id" {
  type        = string
  default     = ""
  description = "eks-wake.ps1가 매 실행마다 설정 — provisioner 재트리거"
}

variable "park_run_id" {
  type        = string
  default     = ""
  description = "eks-park.ps1가 매 실행마다 설정 — provisioner 재트리거"
}
