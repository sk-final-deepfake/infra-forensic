# Fabric SG 8088 규칙 idempotent 적용 (중복 시 스킵)
param(
    [Parameter(Mandatory = $true)][string]$FabricSecurityGroupId,
    [Parameter(Mandatory = $true)][string]$ClusterSecurityGroupId,
    [string]$Region = "ap-northeast-2"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Fabric SG 8088 rule ===" -ForegroundColor Cyan

$rules = aws ec2 describe-security-group-rules `
    --filters "Name=group-id,Values=$FabricSecurityGroupId" `
    --region $Region `
    --output json | ConvertFrom-Json

$exists = @($rules.SecurityGroupRules | Where-Object {
    -not $_.IsEgress -and $_.FromPort -eq 8088 -and $_.ToPort -eq 8088 `
        -and $_.ReferencedGroupInfo.GroupId -eq $ClusterSecurityGroupId
}).Count -gt 0

if ($exists) {
    Write-Host "Rule already exists — skip"
    exit 0
}

$perm = "IpProtocol=tcp,FromPort=8088,ToPort=8088,UserIdGroupPairs=[{GroupId=$ClusterSecurityGroupId,Description=EKS-cluster-SG-to-Gateway}]"
$out = aws ec2 authorize-security-group-ingress `
    --group-id $FabricSecurityGroupId `
    --ip-permissions $perm `
    --region $Region 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "Rule created." -ForegroundColor Green
    exit 0
}

if ($out -match "InvalidPermission.Duplicate") {
    Write-Host "Rule already exists (duplicate) — OK"
    exit 0
}

throw ($out | Out-String)
