# Fabric EC2 stop — Park 시 호출
param(
    [Parameter(Mandatory = $true)]
    [string]$InstanceId,
    [string]$Region = "ap-northeast-2"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Fabric EC2 stop: $InstanceId ===" -ForegroundColor Yellow

$state = aws ec2 describe-instances `
    --instance-ids $InstanceId `
    --region $Region `
    --query "Reservations[0].Instances[0].State.Name" `
    --output text

Write-Host "Current state: $state"

if ($state -eq "stopped") {
    Write-Host "EC2 already stopped." -ForegroundColor Green
    exit 0
}

if ($state -eq "running") {
  # Gateway graceful stop (best-effort via SSM)
  $ping = aws ssm describe-instance-information `
      --filters "Key=InstanceIds,Values=$InstanceId" `
      --region $Region `
      --query "InstanceInformationList[0].PingStatus" `
      --output text 2>$null
  if ($ping -eq "Online") {
      $cmdId = aws ssm send-command `
          --instance-ids $InstanceId `
          --document-name "AWS-RunShellScript" `
          --parameters 'commands=sudo systemctl stop forenshield-fabric-gateway || true' `
          --region $Region `
          --query "Command.CommandId" `
          --output text
      Start-Sleep -Seconds 15
  }
}

if ($state -ne "stopping") {
    Write-Host "Stopping EC2..."
    aws ec2 stop-instances --instance-ids $InstanceId --region $Region | Out-Null
}

aws ec2 wait instance-stopped --instance-ids $InstanceId --region $Region
Write-Host "EC2 stopped." -ForegroundColor Green
