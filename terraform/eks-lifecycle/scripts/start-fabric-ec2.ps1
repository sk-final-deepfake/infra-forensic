# Fabric EC2 start + systemd Gateway health (SSM) — Wake 시 호출
param(
    [Parameter(Mandatory = $true)]
    [string]$InstanceId,
    [string]$Region = "ap-northeast-2",
    [int]$SsmTimeoutSeconds = 600
)

$ErrorActionPreference = "Stop"

function Invoke-AwsJson {
    param([string[]]$AwsArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $raw = & aws @AwsArgs 2>&1
    $exit = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($exit -ne 0) {
        throw ($raw | Out-String).Trim()
    }
    return ($raw | Out-String).Trim()
}

Write-Host "=== Fabric EC2 start: $InstanceId ===" -ForegroundColor Cyan

$state = Invoke-AwsJson @(
    "ec2", "describe-instances",
    "--instance-ids", $InstanceId,
    "--region", $Region,
    "--query", "Reservations[0].Instances[0].State.Name",
    "--output", "text"
)

Write-Host "Current state: $state"

if ($state -eq "stopped" -or $state -eq "stopping") {
    Write-Host "Starting EC2..."
    Invoke-AwsJson @("ec2", "start-instances", "--instance-ids", $InstanceId, "--region", $Region) | Out-Null
    & aws ec2 wait instance-running --instance-ids $InstanceId --region $Region
    if ($LASTEXITCODE -ne 0) { throw "ec2 wait instance-running failed" }
}
elseif ($state -ne "running") {
    throw "Unexpected EC2 state: $state"
}
else {
    Write-Host "EC2 already running."
}

Write-Host "Waiting for SSM agent..."
$deadline = (Get-Date).AddSeconds(300)
$ping = ""
while ((Get-Date) -lt $deadline) {
    $ping = Invoke-AwsJson @(
        "ssm", "describe-instance-information",
        "--filters", "Key=InstanceIds,Values=$InstanceId",
        "--region", $Region,
        "--query", "InstanceInformationList[0].PingStatus",
        "--output", "text"
    )
    if ($ping -eq "Online") { break }
    Start-Sleep -Seconds 10
}
if ($ping -ne "Online") {
    throw "SSM agent not online on $InstanceId"
}

$ssmPayload = @{
    DocumentName = "AWS-RunShellScript"
    InstanceIds  = @($InstanceId)
    Parameters   = @{
        commands = @(
            "sudo systemctl start forenshield-fabric-network || true",
            "sleep 45",
            "sudo systemctl start forenshield-fabric-gateway || true",
            "sleep 5",
            "curl -sf http://localhost:8088/health"
        )
    }
} | ConvertTo-Json -Depth 5 -Compress

$inputFile = New-TemporaryFile
try {
    [System.IO.File]::WriteAllText($inputFile.FullName, $ssmPayload)
    $inputUri = "file://$($inputFile.FullName -replace '\\', '/')"

    $cmdId = Invoke-AwsJson @(
        "ssm", "send-command",
        "--cli-input-json", $inputUri,
        "--region", $Region,
        "--query", "Command.CommandId",
        "--output", "text"
    )
}
finally {
    Remove-Item $inputFile.FullName -Force -ErrorAction SilentlyContinue
}

if ([string]::IsNullOrWhiteSpace($cmdId)) {
    throw "SSM send-command returned empty CommandId"
}

Write-Host "SSM command: $cmdId"

$ssmDeadline = (Get-Date).AddSeconds($SsmTimeoutSeconds)
while ((Get-Date) -lt $ssmDeadline) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $invRaw = & aws ssm get-command-invocation `
        --command-id $cmdId `
        --instance-id $InstanceId `
        --region $Region `
        --output json 2>&1
    $exit = $LASTEXITCODE
    $ErrorActionPreference = $prev

    if ($exit -ne 0) {
        $msg = ($invRaw | Out-String)
        if ($msg -match "InvocationDoesNotExist") {
            Start-Sleep -Seconds 5
            continue
        }
        throw $msg.Trim()
    }

    $inv = ($invRaw | Out-String) | ConvertFrom-Json

    if ($inv.Status -eq "Success") {
        Write-Host "Fabric Gateway health OK." -ForegroundColor Green
        if ($inv.StandardOutputContent) { Write-Host $inv.StandardOutputContent }
        exit 0
    }
    if ($inv.Status -in @("Failed", "Cancelled", "TimedOut")) {
        if ($inv.StandardErrorContent) { Write-Host $inv.StandardErrorContent -ForegroundColor Red }
        if ($inv.StandardOutputContent) { Write-Host $inv.StandardOutputContent }
        throw "SSM command failed: $($inv.Status)"
    }

    Start-Sleep -Seconds 10
}

throw "SSM command timed out after ${SsmTimeoutSeconds}s"
