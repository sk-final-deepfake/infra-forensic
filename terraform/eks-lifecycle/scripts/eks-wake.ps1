# EKS Wake — 클러스터 + Bootstrap + RDS/EC2/Pod/Health 자동화
$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

if (-not (Test-Path "terraform.tfvars")) { Write-Error "terraform.tfvars 없음." }
if (-not (Test-Path "secrets.tfvars")) { Write-Error "secrets.tfvars 없음." }

$env:AWS_PROFILE = if ($env:AWS_PROFILE) { $env:AWS_PROFILE } else { "forenshield" }
$env:AWS_REGION  = if ($env:AWS_REGION)  { $env:AWS_REGION }  else { "ap-northeast-2" }

$wakeRunId = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString()
$commonVars = @(
    "-var-file=terraform.tfvars",
    "-var-file=secrets.tfvars",
    "-var=eks_enabled=true",
    "-var=wake_automation_enabled=true",
    "-var=park_automation_enabled=true",
    "-var=wake_run_id=$wakeRunId"
)

Write-Host "=== EKS Wake Phase 1: RDS/EC2 + EKS cluster ===" -ForegroundColor Green
Write-Host "wake_run_id=$wakeRunId"

terraform init -input=false

$phase1 = $commonVars + @("-var=bootstrap_enabled=false", "-var=install_ebs_csi=false", "-auto-approve")
terraform apply @phase1
if ($LASTEXITCODE -ne 0) { throw "Phase 1 failed (exit $LASTEXITCODE)" }

Write-Host ""
Write-Host "=== IRSA trust patch (EBS CSI + App S3 + ALB Controller) ===" -ForegroundColor Cyan
& "$PSScriptRoot\patch-ebs-csi-trust.ps1"
& "$PSScriptRoot\patch-irsa-trust.ps1"
& "$PSScriptRoot\patch-alb-controller-trust.ps1"

Write-Host ""
Write-Host "=== EKS Wake Phase 1b: EBS CSI addon ===" -ForegroundColor Green
$phase1b = $commonVars + @("-var=bootstrap_enabled=false", "-var=install_ebs_csi=true", "-auto-approve")
terraform apply @phase1b
if ($LASTEXITCODE -ne 0) { throw "Phase 1b failed (exit $LASTEXITCODE)" }

Write-Host ""
Write-Host "=== Subnet tags (ALB auto-discovery) ===" -ForegroundColor Cyan
& "$PSScriptRoot\patch-subnet-tags.ps1"

Write-Host ""
Write-Host "=== EKS Wake Phase 2: Bootstrap + Pod/Health ===" -ForegroundColor Green

& "$PSScriptRoot\init-helm-repos.ps1"

$phase2 = $commonVars + @("-var=bootstrap_enabled=true", "-var=install_ebs_csi=true", "-auto-approve")
terraform apply @phase2
if ($LASTEXITCODE -ne 0) { throw "Phase 2 failed (exit $LASTEXITCODE)" }

Write-Host ""
Write-Host "=== Terraform 출력 ===" -ForegroundColor Cyan
terraform output

Write-Host ""
Write-Host "Wake 완료." -ForegroundColor Green
