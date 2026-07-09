# Wake 후 (Method B): EKS ai-fastapi consumer + VPN→GPU Gateway health + GPU worker 중지
# 경로: Backend → RabbitMQ(EKS) → ai-fastapi Pod → VPN → GPU Gateway :8000/infer
#
# 환경변수:
#   AI_GATEWAY_URL         기본: app-config ConfigMap 또는 http://192.168.0.34:8000
#   ANALYSIS_QUEUE         기본: forenshield.analysis.queue
#   GPU_SSH_HOST           예: 58.151.205.220 (GPU SSH — worker 중지·Gateway 로컬 확인)
#   GPU_SSH_USER           기본 sk4team
#   GPU_SSH_KEY_PATH       기본 %USERPROFILE%\.ssh\id_ed25519 또는 id_rsa
#   GPU_REMOTE_ROOT        기본 forenShield-ai
#   GPU_GATEWAY_LOCAL_URL  GPU SSH 내부 health URL, 기본 http://127.0.0.1:8000
#   SKIP_GPU_SYNC=1        GPU SSH 단계 건너뛰기
#   ENABLE_RABBITMQ_NODEPORT=1  (레거시 PoC) GPU→RabbitMQ NodePort apply — Method B에선 불필요

param(
    [string]$ClusterName = "forenshield",
    [string]$Region = "ap-northeast-2",
    [string]$Namespace = "forenshield",
    [int]$NodePort = 31624
)

$ErrorActionPreference = "Stop"

function Invoke-KubectlText {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $raw = & kubectl @Arguments 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    $text = @(
        $raw | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message }
            else { "$_" }
        } | Where-Object { $_ -and $_ -notmatch '^\s*Warning:' }
    ) -join "`n"
    if ($code -ne 0) {
        throw "kubectl failed (exit $code): $text"
    }
    return $text.Trim()
}

function Get-AiGatewayUrl {
    if ($env:AI_GATEWAY_URL) {
        return $env:AI_GATEWAY_URL.Trim().TrimEnd("/")
    }
    try {
        $fromCm = Invoke-KubectlText -Arguments @(
            "get", "configmap", "app-config", "-n", $Namespace,
            "-o", "jsonpath={.data.AI_GATEWAY_URL}"
        )
        if ($fromCm) {
            return $fromCm.Trim().TrimEnd("/")
        }
    } catch {
        Write-Host "WARN: could not read AI_GATEWAY_URL from app-config: $_" -ForegroundColor Yellow
    }
    return "http://192.168.0.34:8000"
}

function Test-AnalysisQueueConsumer {
    param(
        [string]$QueueName,
        [int]$ExpectedConsumers = 1
    )

    $raw = Invoke-KubectlText -Arguments @(
        "exec", "-n", $Namespace, "rabbitmq-0", "--",
        "rabbitmqctl", "list_queues", "name", "messages", "consumers"
    )

    $line = $raw -split "`n" | Where-Object { $_ -match "^\s*$([regex]::Escape($QueueName))\s" } | Select-Object -First 1
    if (-not $line) {
        throw "Queue '$QueueName' not found in rabbitmqctl output."
    }

    $parts = ($line -replace '\s+', ' ').Trim() -split ' '
    if ($parts.Count -lt 3) {
        throw "Unexpected queue line: $line"
    }

    $messages = [int]$parts[1]
    $consumers = [int]$parts[2]
    Write-Host "Queue $QueueName messages=$messages consumers=$consumers" -ForegroundColor Green

    if ($consumers -eq 0) {
        throw "No consumer on $QueueName — ai-fastapi consumer가 떠 있는지 확인하세요."
    }
    if ($consumers -gt $ExpectedConsumers) {
        throw "consumers=$consumers on $QueueName — GPU gpu_worker가 같이 떠 있으면 중지하세요 (Method B는 ai-fastapi만 consume)."
    }
    if ($consumers -lt $ExpectedConsumers) {
        Write-Host "WARN: consumers=$consumers (expected $ExpectedConsumers)." -ForegroundColor Yellow
    }
}

function Test-EksToGpuGateway {
    param([string]$GatewayUrl)

    $healthUrl = "$GatewayUrl/health"
    $inferUrl = "$GatewayUrl/infer"
    Write-Host "EKS ai-fastapi → GPU Gateway: $healthUrl (+ POST $inferUrl route check)"

    $py = @"
import os, sys, urllib.request
url = os.environ['GW_HEALTH']
try:
    with urllib.request.urlopen(url, timeout=20) as r:
        body = r.read(200).decode('utf-8', 'replace')
        print(f'HTTP {r.status} {body[:120]}')
except Exception as e:
    print(f'FAIL: {e}', file=sys.stderr)
    sys.exit(1)
"@

    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $raw = & kubectl exec -n $Namespace "deploy/ai-fastapi" -- env "GW_HEALTH=$healthUrl" python -c $py 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev

    $text = @(
        $raw | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message }
            else { "$_" }
        }
    ) -join "`n"

    if ($code -ne 0) {
        throw "EKS→GPU Gateway health failed: $text"
    }
    Write-Host $text -ForegroundColor Green

    $pyInfer = @"
import os, sys, urllib.request, json
base = os.environ['GW_BASE']
req = urllib.request.Request(
    base.rstrip('/') + '/infer',
    data=json.dumps({'case_id':'wake-probe','evidence_id':0,'analysis_request_id':0,'evidence_path':'s3://probe/probe.mp4'}).encode(),
    headers={'Content-Type': 'application/json'},
    method='POST',
)
try:
    urllib.request.urlopen(req, timeout=20)
except urllib.error.HTTPError as e:
    if e.code in (404, 405):
        print(f'FAIL: POST /infer returned {e.code} — GPU에 Mock 서버만 떠 있을 수 있습니다.', file=sys.stderr)
        sys.exit(1)
    if e.code in (422, 500, 503):
        print(f'POST /infer route OK (HTTP {e.code}, inference deps or S3 expected)')
        sys.exit(0)
    print(f'FAIL: POST /infer HTTP {e.code}', file=sys.stderr)
    sys.exit(1)
"@

    $prev2 = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $inferRaw = & kubectl exec -n $Namespace "deploy/ai-fastapi" -- env "GW_BASE=$GatewayUrl" python -c $pyInfer 2>&1
    $inferCode = $LASTEXITCODE
    $ErrorActionPreference = $prev2
    $inferText = @(
        $inferRaw | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message }
            else { "$_" }
        }
    ) -join "`n"
    if ($inferCode -ne 0) {
        throw "EKS→GPU Gateway /infer check failed: $inferText"
    }
    Write-Host $inferText -ForegroundColor Green
}

if ($env:RABBITMQ_NODEPORT) {
    $NodePort = [int]$env:RABBITMQ_NODEPORT
}

$ScriptDir = $PSScriptRoot
$EksLifecycleRoot = Split-Path $ScriptDir -Parent
$TerraformRoot = Split-Path $EksLifecycleRoot -Parent
$InfraRoot = Split-Path $TerraformRoot -Parent
$ServiceManifest = Join-Path $InfraRoot "config\k8s\rabbitmq\rabbitmq-external.yaml"
$analysisQueue = if ($env:ANALYSIS_QUEUE) { $env:ANALYSIS_QUEUE } else { "forenshield.analysis.queue" }
$gatewayUrl = Get-AiGatewayUrl

Write-Host "=== Method B sync (ai-fastapi + GPU Gateway) ===" -ForegroundColor Cyan
Write-Host "AI_GATEWAY_URL=$gatewayUrl"
Write-Host "ANALYSIS_QUEUE=$analysisQueue"

aws eks update-kubeconfig --name $ClusterName --region $Region | Out-Null

Write-Host "Waiting for rabbitmq-0..."
Invoke-KubectlText -Arguments @("wait", "--for=condition=ready", "pod/rabbitmq-0", "-n", $Namespace, "--timeout=300s") | Out-Null

Write-Host "Waiting for ai-fastapi..."
Invoke-KubectlText -Arguments @("wait", "--for=condition=ready", "pod", "-l", "app=ai-fastapi", "-n", $Namespace, "--timeout=300s") | Out-Null

Test-AnalysisQueueConsumer -QueueName $analysisQueue -ExpectedConsumers 1
Test-EksToGpuGateway -GatewayUrl $gatewayUrl

if ($env:ENABLE_RABBITMQ_NODEPORT -eq "1") {
    Write-Host "ENABLE_RABBITMQ_NODEPORT=1 — applying legacy NodePort (PoC GPU worker용)..." -ForegroundColor Yellow
    if (-not (Test-Path $ServiceManifest)) {
        throw "Manifest not found: $ServiceManifest"
    }
    Invoke-KubectlText -Arguments @("apply", "-f", $ServiceManifest) | Write-Host

    $nodeName = Invoke-KubectlText -Arguments @(
        "get", "pod", "rabbitmq-0", "-n", $Namespace,
        "-o", "jsonpath={.spec.nodeName}"
    )
    $nodeIp = Invoke-KubectlText -Arguments @(
        "get", "node", $nodeName,
        "-o", "jsonpath={.status.addresses[?(@.type=='InternalIP')].address}"
    )
    Write-Host "Legacy NodePort: $nodeIp`:$NodePort (GPU worker PoC only)" -ForegroundColor Yellow
} else {
    Write-Host "RabbitMQ NodePort skipped (Method B — GPU는 RabbitMQ에 연결하지 않음)." -ForegroundColor DarkGray
}

if ($env:SKIP_GPU_SYNC -eq "1") {
    Write-Host "SKIP_GPU_SYNC=1 — GPU SSH 단계 건너뜀."
    Write-Host "Method B sync done." -ForegroundColor Green
    exit 0
}

$gpuHost = $env:GPU_SSH_HOST
if (-not $gpuHost) {
    Write-Host ""
    Write-Host "GPU_SSH_HOST not set — EKS 검증만 완료. GPU worker 중지·Gateway 로컬 확인은 수동:" -ForegroundColor Yellow
    Write-Host "  `$env:GPU_SSH_HOST = '58.151.205.220'"
    Write-Host "  `$env:GPU_SSH_USER = 'sk4team'"
    Write-Host "  `$env:GPU_SSH_KEY_PATH = `"`$env:USERPROFILE\.ssh\id_ed25519`""
    Write-Host "  pkill -f gpu_worker.rabbitmq_worker"
    $localGwHint = if ($env:GPU_GATEWAY_LOCAL_URL) { $env:GPU_GATEWAY_LOCAL_URL.TrimEnd("/") } else { "http://127.0.0.1:8000" }
    Write-Host "  curl -sf $localGwHint/health"
    Write-Host "Method B sync done (EKS only)." -ForegroundColor Green
    exit 0
}

$gpuUser = if ($env:GPU_SSH_USER) { $env:GPU_SSH_USER } else { "sk4team" }
$remoteRoot = if ($env:GPU_REMOTE_ROOT) { $env:GPU_REMOTE_ROOT } else { "forenShield-ai" }
$gpuGatewayLocal = if ($env:GPU_GATEWAY_LOCAL_URL) { $env:GPU_GATEWAY_LOCAL_URL.TrimEnd("/") } else { "http://127.0.0.1:8000" }

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
    throw "SSH key not found. Set GPU_SSH_KEY_PATH or install key under ~/.ssh."
}

$sshTarget = "${gpuUser}@${gpuHost}"
$sshArgs = @(
    "-i", $keyPath,
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "ConnectTimeout=20"
)

Write-Host "GPU Method B check via $sshTarget ..."

$remoteBash = @"
set -euo pipefail
GW_LOCAL='$gpuGatewayLocal'
echo '--- stop legacy gpu_worker (Method B uses EKS ai-fastapi consumer) ---'
if pgrep -af 'gpu_worker.rabbitmq_worker' >/dev/null 2>&1; then
  pkill -f 'gpu_worker.rabbitmq_worker' || true
  sleep 1
fi
if pgrep -af 'gpu_worker.rabbitmq_worker' >/dev/null 2>&1; then
  echo 'ERROR: gpu_worker still running — stop it before Method B analysis.' >&2
  pgrep -af 'gpu_worker.rabbitmq_worker' >&2 || true
  exit 1
fi
echo 'gpu_worker: not running (OK)'

echo '--- GPU Gateway local health ---'
HEALTH="`${GW_LOCAL%/}/health"
INFER="`${GW_LOCAL%/}/infer"
if command -v curl >/dev/null 2>&1; then
  curl -sfS --max-time 15 "`$HEALTH"
  echo ""
elif command -v python3 >/dev/null 2>&1; then
  python3 -c "import urllib.request; r=urllib.request.urlopen('`$HEALTH', timeout=15); print(r.read(200).decode())"
else
  echo "WARN: no curl/python3 for local gateway health" >&2
fi

echo '--- POST /infer route (expect 422/500/503, not 404) ---'
PROBE='{"case_id":"wake","evidence_id":0,"analysis_request_id":0,"evidence_path":"s3://probe/x.mp4"}'
if command -v curl >/dev/null 2>&1; then
  code="`$(curl -sS -o /tmp/fs_infer_probe.out -w '%{http_code}' -X POST "`$INFER" -H 'Content-Type: application/json' -d "`$PROBE" --max-time 20 || true)"
  echo "POST /infer HTTP `$code"
  if [ "`$code" = "404" ] || [ "`$code" = "405" ]; then
    echo 'ERROR: /infer not found — deploy ai-forensic with infer router on GPU' >&2
    exit 1
  fi
fi

if systemctl is-active --quiet forenshield-ai-gateway 2>/dev/null; then
  echo 'systemd forenshield-ai-gateway: active'
elif systemctl is-active --quiet forenshield-ai-gateway.service 2>/dev/null; then
  echo 'systemd forenshield-ai-gateway.service: active'
else
  echo 'systemd gateway unit not active (manual uvicorn may still be OK if health passed)'
fi

ss -lntp 2>/dev/null | grep -E ':8000\b' || netstat -lntp 2>/dev/null | grep -E ':8000\b' || true
echo 'GPU Method B SSH checks OK'
"@

$remoteBash = $remoteBash -replace "`r`n", "`n"

$remoteBash | & ssh @sshArgs $sshTarget "bash -s"
if ($LASTEXITCODE -ne 0) {
    throw "GPU SSH sync failed (exit $LASTEXITCODE). Check VPN, key auth, Gateway on :8000, and GPU_SSH_* env."
}

Write-Host "Method B sync done: ai-fastapi consumer + GPU Gateway $gatewayUrl" -ForegroundColor Green
