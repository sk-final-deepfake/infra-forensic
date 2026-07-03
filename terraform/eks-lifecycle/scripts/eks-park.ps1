# EKS Park — Control Plane 삭제 + RDS/EC2 stop 자동화
$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

if (-not (Test-Path "terraform.tfvars")) { Write-Error "terraform.tfvars 없음." }

$env:AWS_PROFILE = if ($env:AWS_PROFILE) { $env:AWS_PROFILE } else { "forenshield" }
$env:AWS_REGION  = if ($env:AWS_REGION)  { $env:AWS_REGION }  else { "ap-northeast-2" }

$parkRunId = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString()

Write-Host "=== EKS Park ===" -ForegroundColor Yellow
Write-Host "park_run_id=$parkRunId"

function Ensure-TerraformState {
    $statePath = Join-Path $Root "terraform.tfstate"
    $backupPath = Join-Path $Root "terraform.tfstate.backup"
    $size = if (Test-Path $statePath) { (Get-Item $statePath).Length } else { 0 }
    if ($size -gt 0) { return }

    if (Test-Path $backupPath -and (Get-Item $backupPath).Length -gt 0) {
        Write-Warning "terraform.tfstate 가 비어 있음 — backup 에서 복구합니다."
        Copy-Item $backupPath $statePath -Force
        return
    }
    Write-Error "terraform.tfstate 가 없습니다. terraform init 후 import 또는 Wake 로 state 를 다시 만드세요."
}

function Remove-TerraformIngressState {
    $statePath = Join-Path $Root "terraform.tfstate"
    if (-not (Test-Path $statePath) -or (Get-Item $statePath).Length -eq 0) { return }

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $stateList = terraform state list 2>$null
        foreach ($addr in @(
                "module.bootstrap[0].kubernetes_ingress_v1.app",
                "module.bootstrap[0].kubernetes_ingress_v1.argocd",
                "module.bootstrap[0].kubernetes_namespace_v1.forenshield"
            )) {
            if ($stateList -notcontains $addr) { continue }
            terraform state rm $addr 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Host "state 제거: $addr" }
        }
    } finally {
        $ErrorActionPreference = $prevEap
    }
}

function Invoke-TerraformApply {
    param([string[]]$ExtraVars)
    $applyArgs = @("-auto-approve") + $ExtraVars
    if (Test-Path "terraform.tfvars") { $applyArgs = @("-var-file=terraform.tfvars") + $applyArgs }
    if (Test-Path "secrets.tfvars") { $applyArgs = @("-var-file=secrets.tfvars") + $applyArgs }
    terraform apply @applyArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

terraform init -input=false
Ensure-TerraformState

$clusterName = "forenshield"
if (Test-Path "terraform.tfvars") {
    $tfvars = Get-Content "terraform.tfvars" -Raw
    if ($tfvars -match 'cluster_name\s*=\s*"([^"]+)"') { $clusterName = $Matches[1] }
}

# 1단계: 클러스터가 살아 있는 동안 bootstrap(Helm/K8s)만 제거
Write-Host ""
Write-Host "=== Park Phase 1: bootstrap 제거 (EKS 유지) ===" -ForegroundColor Cyan
powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\park-k8s-cleanup.ps1" -ClusterName $clusterName -Region $env:AWS_REGION
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Remove-TerraformIngressState

$phase1Vars = @(
    "-var=eks_enabled=true",
    "-var=bootstrap_enabled=false",
    "-var=wake_automation_enabled=false",
    "-var=park_automation_enabled=false"
)
terraform apply -auto-approve @(
    @("-var-file=terraform.tfvars") +
    $(if (Test-Path "secrets.tfvars") { @("-var-file=secrets.tfvars") } else { @() }) +
    $phase1Vars
)
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Park Phase 1 실패 — k8s cleanup 재실행 후 state 우회하고 재시도합니다."
    powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\park-k8s-cleanup.ps1" -ClusterName $clusterName -Region $env:AWS_REGION
    Remove-TerraformIngressState
    terraform apply -auto-approve @(
        @("-var-file=terraform.tfvars") +
        $(if (Test-Path "secrets.tfvars") { @("-var-file=secrets.tfvars") } else { @() }) +
        $phase1Vars
    )
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# 2단계: EKS 삭제 + RDS/EC2 stop
Write-Host ""
Write-Host "=== Park Phase 2: EKS 삭제 + RDS/EC2 stop ===" -ForegroundColor Cyan
Invoke-TerraformApply @(
    "-var=eks_enabled=false",
    "-var=bootstrap_enabled=false",
    "-var=wake_automation_enabled=false",
    "-var=park_automation_enabled=true",
    "-var=park_run_id=$parkRunId"
)

Write-Host ""
Write-Host "Park 완료." -ForegroundColor Green
