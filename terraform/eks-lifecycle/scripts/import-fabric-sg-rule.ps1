# Fabric SG 8088 규칙이 이미 AWS에 있으면 Terraform state로 import
param(
    [string]$FabricSecurityGroupId = "sg-0992309b24773bb7f",
    [string]$Region = "ap-northeast-2"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

$env:AWS_PROFILE = if ($env:AWS_PROFILE) { $env:AWS_PROFILE } else { "forenshield" }

$clusterSg = (terraform output -raw cluster_security_group_id 2>$null)
if (-not $clusterSg) {
    Write-Host "cluster_security_group_id output 없음 — import 스킵"
    exit 0
}

$resource = "module.bootstrap[0].aws_security_group_rule.fabric_from_eks"
$prevEap = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
terraform state show $resource 1>$null 2>$null
$inState = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $prevEap

if ($inState) {
    Write-Host "Fabric SG rule already in state — skip import"
    exit 0
}

$rulesJson = aws ec2 describe-security-group-rules `
    --filters "Name=group-id,Values=$FabricSecurityGroupId" `
    --region $Region `
    --output json | ConvertFrom-Json

$match = $rulesJson.SecurityGroupRules | Where-Object {
    -not $_.IsEgress `
        -and $_.FromPort -eq 8088 `
        -and $_.ToPort -eq 8088 `
        -and $_.ReferencedGroupInfo.GroupId -eq $clusterSg
} | Select-Object -First 1

if (-not $match) {
    Write-Host "No existing Fabric SG rule for $clusterSg -> 8088 — Terraform will create"
    exit 0
}

$ruleId = $match.SecurityGroupRuleId
Write-Host "Importing existing Fabric SG rule: $ruleId"
terraform import $resource $ruleId
if ($LASTEXITCODE -ne 0) { throw "terraform import failed for $ruleId" }
Write-Host "Import OK." -ForegroundColor Green
