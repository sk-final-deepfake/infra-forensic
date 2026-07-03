# Terraform external data — Fabric SG 8088 규칙 존재 여부
$ErrorActionPreference = "Stop"
$input = [Console]::In.ReadToEnd() | ConvertFrom-Json

$fabricSg = $input.fabric_sg
$clusterSg = $input.cluster_sg
$region = if ($input.region) { $input.region } else { "ap-northeast-2" }

$rules = aws ec2 describe-security-group-rules `
    --filters "Name=group-id,Values=$fabricSg" `
    --region $region `
    --output json | ConvertFrom-Json

$exists = @($rules.SecurityGroupRules | Where-Object {
    -not $_.IsEgress `
        -and $_.FromPort -eq 8088 `
        -and $_.ToPort -eq 8088 `
        -and $_.ReferencedGroupInfo.GroupId -eq $clusterSg
}).Count -gt 0

@{ exists = $(if ($exists) { "true" } else { "false" }) } | ConvertTo-Json -Compress
