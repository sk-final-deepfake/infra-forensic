locals {
  wake_automation = var.eks_enabled && var.bootstrap_enabled && var.wake_automation_enabled
  wake_trigger    = var.wake_run_id != "" ? var.wake_run_id : try(aws_eks_cluster.this[0].id, "none")
  park_automation = !var.eks_enabled && var.park_automation_enabled
  park_trigger    = var.park_run_id != "" ? var.park_run_id : "park"
}

# Wake 1단계: RDS·Fabric EC2를 EKS와 병렬로 기동 (handbook 순서)
resource "terraform_data" "wake_rds_start" {
  count = local.wake_automation && var.rds_instance_identifier != "" ? 1 : 0

  triggers_replace = [local.wake_trigger]

  provisioner "local-exec" {
    command     = "powershell -ExecutionPolicy Bypass -File ${path.module}/scripts/start-rds.ps1 -DbInstanceId ${var.rds_instance_identifier} -Region ${var.aws_region}"
    working_dir = path.module
  }
}

resource "terraform_data" "wake_fabric_ec2_start" {
  count = local.wake_automation && var.fabric_instance_id != "" ? 1 : 0

  triggers_replace = [local.wake_trigger]

  provisioner "local-exec" {
    command     = "powershell -ExecutionPolicy Bypass -File ${path.module}/scripts/start-fabric-ec2.ps1 -InstanceId ${var.fabric_instance_id} -Region ${var.aws_region}"
    working_dir = path.module
  }
}

resource "terraform_data" "wake_fabric_sg_rule" {
  count = var.eks_enabled && var.bootstrap_enabled && var.wake_automation_enabled && var.fabric_security_group_id != "" ? 1 : 0

  triggers_replace = [
    local.wake_trigger,
    aws_eks_cluster.this[0].vpc_config[0].cluster_security_group_id,
  ]

  provisioner "local-exec" {
    command     = "powershell -ExecutionPolicy Bypass -File ${path.module}/scripts/ensure-fabric-sg-rule.ps1 -FabricSecurityGroupId ${var.fabric_security_group_id} -ClusterSecurityGroupId ${aws_eks_cluster.this[0].vpc_config[0].cluster_security_group_id} -Region ${var.aws_region}"
    working_dir = path.module
  }

  depends_on = [aws_eks_cluster.this]
}

# Park: RDS·Fabric EC2 정지
resource "terraform_data" "park_rds_stop" {
  count = local.park_automation && var.rds_instance_identifier != "" ? 1 : 0

  triggers_replace = [local.park_trigger]

  provisioner "local-exec" {
    command     = "powershell -ExecutionPolicy Bypass -File ${path.module}/scripts/stop-rds.ps1 -DbInstanceId ${var.rds_instance_identifier} -Region ${var.aws_region}"
    working_dir = path.module
  }
}

resource "terraform_data" "park_fabric_ec2_stop" {
  count = local.park_automation && var.fabric_instance_id != "" ? 1 : 0

  triggers_replace = [local.park_trigger]

  provisioner "local-exec" {
    command     = "powershell -ExecutionPolicy Bypass -File ${path.module}/scripts/stop-fabric-ec2.ps1 -InstanceId ${var.fabric_instance_id} -Region ${var.aws_region}"
    working_dir = path.module
  }
}
