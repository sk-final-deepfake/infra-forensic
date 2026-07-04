# Wake 후: RabbitMQ NodePort 보장 + GPU worker .env(RABBITMQ_HOST/PORT) 갱신 + worker 재시작
# 사전: VPN, kubectl, (GPU 동기화 시) SSH 키
#
# 환경변수 (GPU 동기화할 때만 설정):
#   GPU_SSH_HOST       예: 58.127.241.84 또는 welabs (VPN에서 도달 가능)
#   GPU_SSH_USER       기본 sk4team
#   GPU_SSH_KEY_PATH   기본 %USERPROFILE%\.ssh\id_ed25519 또는 id_rsa
#   GPU_REMOTE_ROOT    홈 기준 상대경로, 기본 forenShield-ai
#   RABBITMQ_NODEPORT  기본 31624
#   SKIP_GPU_SYNC=1    GPU 단계 건너뛰기

param(
    [string]$ClusterName = "forenshield",
    [string]$Region = "ap-northeast-2",
    [string]$Namespace = "forenshield",
    [int]$NodePort = 31624
)

$ErrorActionPreference = "Stop"

if ($env:RABBITMQ_NODEPORT) {
    $NodePort = [int]$env:RABBITMQ_NODEPORT
}

$ScriptDir = $PSScriptRoot
$EksLifecycleRoot = Split-Path $ScriptDir -Parent
$TerraformRoot = Split-Path $EksLifecycleRoot -Parent
$InfraRoot = Split-Path $TerraformRoot -Parent
$ServiceManifest = Join-Path $InfraRoot "config\k8s\rabbitmq\rabbitmq-external.yaml"

Write-Host "=== Sync GPU RabbitMQ (NodePort + worker) ===" -ForegroundColor Cyan

aws eks update-kubeconfig --name $ClusterName --region $Region | Out-Null

Write-Host "Waiting for rabbitmq-0..."
kubectl wait --for=condition=ready pod/rabbitmq-0 -n $Namespace --timeout=300s

if (-not (Test-Path $ServiceManifest)) {
    throw "Manifest not found: $ServiceManifest"
}

Write-Host "Applying rabbitmq-external NodePort..."
kubectl apply -f $ServiceManifest

$deadline = (Get-Date).AddMinutes(3)
$endpointsReady = $false
while ((Get-Date) -lt $deadline) {
    $ep = kubectl get endpoints rabbitmq-external -n $Namespace -o jsonpath="{.subsets[0].addresses[0].ip}" 2>$null
    if ($ep) {
        Write-Host "rabbitmq-external endpoints OK ($ep)" -ForegroundColor Green
        $endpointsReady = $true
        break
    }
    Start-Sleep -Seconds 5
}
if (-not $endpointsReady) {
    throw "rabbitmq-external has no endpoints. Check RabbitMQ pod labels/selector."
}

$nodeName = kubectl get pod rabbitmq-0 -n $Namespace -o jsonpath="{.spec.nodeName}"
if (-not $nodeName) {
    throw "Cannot resolve node for rabbitmq-0"
}

$nodeIp = kubectl get node $nodeName -o jsonpath="{.status.addresses[?(@.type=='InternalIP')].address}"
if (-not $nodeIp) {
    throw "Cannot resolve InternalIP for node $nodeName"
}

Write-Host "RabbitMQ node=$nodeName ip=$nodeIp nodePort=$NodePort" -ForegroundColor Green

# Optional local reachability check (VPN)
try {
    $tnc = Test-NetConnection -ComputerName $nodeIp -Port $NodePort -WarningAction SilentlyContinue
    if ($tnc.TcpTestSucceeded) {
        Write-Host "TCP $nodeIp`:$NodePort reachable from this machine." -ForegroundColor Green
    } else {
        Write-Host "WARN: TCP $nodeIp`:$NodePort not reachable from here (VPN/SG?). GPU may still reach it." -ForegroundColor Yellow
    }
} catch {
    Write-Host "WARN: reachability check skipped: $_" -ForegroundColor Yellow
}

if ($env:SKIP_GPU_SYNC -eq "1") {
    Write-Host "SKIP_GPU_SYNC=1 — GPU .env update skipped."
    Write-Host "Manual: RABBITMQ_HOST=$nodeIp  RABBITMQ_PORT=$NodePort"
    exit 0
}

$gpuHost = $env:GPU_SSH_HOST
if (-not $gpuHost) {
    Write-Host ""
    Write-Host "GPU_SSH_HOST not set — NodePort only. Set env to auto-update GPU worker:" -ForegroundColor Yellow
    Write-Host "  `$env:GPU_SSH_HOST = '58.127.241.84'"
    Write-Host "  `$env:GPU_SSH_USER = 'sk4team'"
    Write-Host "  `$env:GPU_SSH_KEY_PATH = `"`$env:USERPROFILE\.ssh\id_ed25519`""
    Write-Host "Then: RABBITMQ_HOST=$nodeIp  RABBITMQ_PORT=$NodePort"
    exit 0
}

$gpuUser = if ($env:GPU_SSH_USER) { $env:GPU_SSH_USER } else { "sk4team" }
$remoteRoot = if ($env:GPU_REMOTE_ROOT) { $env:GPU_REMOTE_ROOT } else { "forenShield-ai" }

$keyPath = $env:GPU_SSH_KEY_PATH
if (-not $keyPath) {
    $candidates = @(
        (Join-Path $env:USERPROFILE ".ssh\id_ed25519"),
        (Join-Path $env:USERPROFILE ".ssh\id_rsa")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $keyPath = $c; break }
    }
}
if (-not $keyPath -or -not (Test-Path $keyPath)) {
    throw "SSH key not found. Set GPU_SSH_KEY_PATH or install key under ~/.ssh (password SSH is not automated)."
}

$sshTarget = "${gpuUser}@${gpuHost}"
$sshArgs = @(
    "-i", $keyPath,
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "ConnectTimeout=20"
)

Write-Host "Updating GPU worker .env via $sshTarget ..."

# Remote bash: set HOST/PORT separately (gpu_worker/config.py uses both)
$remoteBash = @"
set -euo pipefail
ROOT="`$HOME/$remoteRoot"
ENV_FILE="`$ROOT/gpu_worker/.env"
mkdir -p "`$ROOT/logs" "`$ROOT/gpu_worker"
touch "`$ENV_FILE"
# drop old host/port lines (including host:port form)
grep -vE '^(RABBITMQ_HOST|RABBITMQ_PORT)=' "`$ENV_FILE" > "`$ENV_FILE.tmp" || true
printf 'RABBITMQ_HOST=%s\n' '$nodeIp' >> "`$ENV_FILE.tmp"
printf 'RABBITMQ_PORT=%s\n' '$NodePort' >> "`$ENV_FILE.tmp"
mv "`$ENV_FILE.tmp" "`$ENV_FILE"
echo "Updated `$ENV_FILE:"
grep -E '^(RABBITMQ_HOST|RABBITMQ_PORT)=' "`$ENV_FILE"
cd "`$ROOT"
pkill -f 'gpu_worker.rabbitmq_worker' || true
sleep 1
nohup python -m gpu_worker.rabbitmq_worker >> logs/worker.log 2>&1 &
sleep 2
echo '--- worker.log (tail) ---'
tail -n 30 logs/worker.log || true
"@

$remoteBash = $remoteBash -replace "`r`n", "`n"

$remoteBash | & ssh @sshArgs $sshTarget "bash -s"
if ($LASTEXITCODE -ne 0) {
    throw "GPU SSH sync failed (exit $LASTEXITCODE). Check VPN, key auth, and GPU_SSH_* env."
}

Write-Host "GPU RabbitMQ sync done: ${nodeIp}:$NodePort" -ForegroundColor Green
