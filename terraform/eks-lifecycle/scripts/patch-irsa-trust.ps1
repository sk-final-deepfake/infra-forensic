# 클러스터 재생성 후 IRSA trust policy 갱신
param(
    [string]$RoleName = "forenshield-app-s3-role",
    [string]$ServiceAccount = "system:serviceaccount:forenshield:forenshield-app"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

$env:AWS_PROFILE = if ($env:AWS_PROFILE) { $env:AWS_PROFILE } else { "forenshield" }

$oidcArn = terraform output -raw oidc_provider_arn 2>$null
$oidcUrl = terraform output -raw oidc_provider_url 2>$null
if (-not $oidcArn -or -not $oidcUrl) {
    Write-Error "terraform output oidc 없음. eks_enabled=true 상태에서 실행하세요."
}

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
Write-Host "IRSA trust updated for $RoleName" -ForegroundColor Green
