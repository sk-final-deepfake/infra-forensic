# RDS start (idempotent) — Wake 시 Terraform local-exec에서 호출
param(
    [Parameter(Mandatory = $true)]
    [string]$DbInstanceId,
    [string]$Region = "ap-northeast-2"
)

$ErrorActionPreference = "Stop"

Write-Host "=== RDS start: $DbInstanceId ===" -ForegroundColor Cyan

$status = aws rds describe-db-instances `
    --db-instance-identifier $DbInstanceId `
    --region $Region `
    --query "DBInstances[0].DBInstanceStatus" `
    --output text

Write-Host "Current status: $status"

switch ($status) {
    "available" {
        Write-Host "RDS already available." -ForegroundColor Green
        exit 0
    }
    "stopped" {
        Write-Host "Starting RDS..."
        aws rds start-db-instance --db-instance-identifier $DbInstanceId --region $Region | Out-Null
    }
    "starting" {
        Write-Host "RDS already starting..."
    }
    default {
        Write-Host "Waiting for RDS (status: $status)..."
    }
}

aws rds wait db-instance-available --db-instance-identifier $DbInstanceId --region $Region
Write-Host "RDS available." -ForegroundColor Green
