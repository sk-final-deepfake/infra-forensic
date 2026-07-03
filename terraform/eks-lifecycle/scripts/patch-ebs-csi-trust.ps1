# EBS CSI IRSA trust — 클러스터 재생성 후 OIDC issuer 갱신
param(
    [string]$RoleName = "forenshield-ebs-csi-role",
    [string]$ServiceAccount = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

$env:AWS_PROFILE = if ($env:AWS_PROFILE) { $env:AWS_PROFILE } else { "forenshield" }

$oidcArn = terraform output -raw oidc_provider_arn
$oidcUrl = terraform output -raw oidc_provider_url
$oidcHost = $oidcUrl -replace "^https://", ""

$trust = @{
    Version = "2012-10-17"
    Statement = @(@{
        Effect = "Allow"
        Principal = @{ Federated = $oidcArn }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = @{
            StringEquals = @{
                "$oidcHost`:aud" = "sts.amazonaws.com"
                "$oidcHost`:sub" = $ServiceAccount
            }
        }
    })
} | ConvertTo-Json -Depth 6 -Compress

$tmp = New-TemporaryFile
[System.IO.File]::WriteAllText($tmp.FullName, $trust)
aws iam update-assume-role-policy --role-name $RoleName --policy-document "file://$($tmp.FullName)"
Remove-Item $tmp.FullName
Write-Host "EBS CSI trust updated for $RoleName" -ForegroundColor Green
