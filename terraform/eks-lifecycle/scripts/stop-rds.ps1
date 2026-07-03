# RDS stop (idempotent) — Park 시 Terraform local-exec에서 호출
param(
    [Parameter(Mandatory = $true)]
    [string]$DbInstanceId,
    [string]$Region = "ap-northeast-2"
)

$ErrorActionPreference = "Stop"

Write-Host "=== RDS stop: $DbInstanceId ===" -ForegroundColor Yellow

$status = aws rds describe-db-instances `
    --db-instance-identifier $DbInstanceId `
    --region $Region `
    --query "DBInstances[0].DBInstanceStatus" `
    --output text

Write-Host "Current status: $status"

switch ($status) {
    "stopped" {
        Write-Host "RDS already stopped." -ForegroundColor Green
        exit 0
    }
    "stopping" {
        Write-Host "RDS already stopping..."
    }
    default {
        Write-Host "Stopping RDS..."
        aws rds stop-db-instance --db-instance-identifier $DbInstanceId --region $Region | Out-Null
    }
}

aws rds wait db-instance-stopped --db-instance-identifier $DbInstanceId --region $Region
Write-Host "RDS stopped." -ForegroundColor Green
