# ALB Controller subnet auto-discovery — Park/Wake 후 public subnet ELB 태그 복구
param(
    [string]$Region = "ap-northeast-2"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

$env:AWS_PROFILE = if ($env:AWS_PROFILE) { $env:AWS_PROFILE } else { "forenshield" }
$env:AWS_REGION  = if ($env:AWS_REGION)  { $env:AWS_REGION }  else { $Region }

if (-not (Test-Path "terraform.tfvars")) {
    Write-Error "terraform.tfvars 없음."
}

function Get-TfvarSubnetIds {
    param([string]$Name)
    $raw = Get-Content "terraform.tfvars" -Raw
    if ($raw -notmatch "(?ms)$Name\s*=\s*\[(.*?)\]") {
        return @()
    }
    $matches[1] -split '[,\s]+' | ForEach-Object { $_.Trim('"').Trim() } | Where-Object { $_ -like "subnet-*" }
}

function Get-TfvarString {
    param([string]$Name)
    $raw = Get-Content "terraform.tfvars" -Raw
    if ($raw -match "$Name\s*=\s*""([^""]+)""") { return $Matches[1] }
    return $null
}

$clusterName = Get-TfvarString "cluster_name"
if (-not $clusterName) { $clusterName = "forenshield" }

$clusterSubnets = Get-TfvarSubnetIds "cluster_subnet_ids"
$privateSubnets = Get-TfvarSubnetIds "private_subnet_ids"
$publicSubnets = $clusterSubnets | Where-Object { $_ -notin $privateSubnets }

if ($publicSubnets.Count -eq 0) {
    Write-Warning "public subnet 을 cluster_subnet_ids - private_subnet_ids 로 찾지 못했습니다."
    exit 0
}

$clusterTag = "kubernetes.io/cluster/$clusterName"

Write-Host "=== Subnet tags (cluster=$clusterName) ===" -ForegroundColor Cyan
Write-Host "Public (elb): $($publicSubnets -join ', ')"
Write-Host "Private (internal-elb): $($privateSubnets -join ', ')"

foreach ($subnetId in $publicSubnets) {
    aws ec2 create-tags `
        --resources $subnetId `
        --region $env:AWS_REGION `
        --tags `
            "Key=kubernetes.io/role/elb,Value=1" `
            "Key=$clusterTag,Value=shared"
    Write-Host "Tagged public: $subnetId" -ForegroundColor Green
}

foreach ($subnetId in $privateSubnets) {
    aws ec2 create-tags `
        --resources $subnetId `
        --region $env:AWS_REGION `
        --tags `
            "Key=kubernetes.io/role/internal-elb,Value=1" `
            "Key=$clusterTag,Value=shared"
    Write-Host "Tagged private: $subnetId" -ForegroundColor Green
}

Write-Host "Subnet tags done." -ForegroundColor Green
