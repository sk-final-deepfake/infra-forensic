# Helm chart repo 캐시 초기화 — Terraform helm provider apply 전 필수
$ErrorActionPreference = "Stop"

Write-Host "=== Helm repo init ===" -ForegroundColor Cyan

if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
    throw "helm CLI not found. Install: https://helm.sh/docs/intro/install/"
}

$repos = @(
    @{ Name = "bitnami"; Url = "https://charts.bitnami.com/bitnami" },
    @{ Name = "eks"; Url = "https://aws.github.io/eks-charts" },
    @{ Name = "argo"; Url = "https://argoproj.github.io/argo-helm" }
)

foreach ($r in $repos) {
    helm repo add $r.Name $r.Url 2>$null | Out-Null
    if ($LASTEXITCODE -gt 1) { throw "helm repo add $($r.Name) failed" }
}

helm repo update
if ($LASTEXITCODE -ne 0) { throw "helm repo update failed" }

Write-Host "Helm repos ready." -ForegroundColor Green
