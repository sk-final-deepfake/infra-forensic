# EKS 워크로드 Ready 대기 + Fabric EKS→Gateway health — Wake bootstrap 후반
param(
    [Parameter(Mandatory = $true)]
    [string]$ClusterName,
    [string]$Region = "ap-northeast-2",
    [string]$Namespace = "forenshield",
    [string]$FabricHealthUrl = "http://10.0.10.224:8088/health",
    [int]$TimeoutSeconds = 900
)

$ErrorActionPreference = "Stop"

Write-Host "=== K8s workload wait: $ClusterName ===" -ForegroundColor Cyan

aws eks update-kubeconfig --name $ClusterName --region $Region --alias forenshield-wake | Out-Null

$timeout = "${TimeoutSeconds}s"

Write-Host "Waiting for nodes..."
kubectl wait --for=condition=Ready nodes --all --timeout=$timeout

Write-Host "Waiting for RabbitMQ..."
kubectl wait --for=condition=ready pod `
    -l app.kubernetes.io/name=rabbitmq `
    -n $Namespace `
    --timeout=$timeout

# On-Prem GPU NodePort (Argo may also apply this; ensure present before health continues)
$InfraRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$RabbitExternal = Join-Path $InfraRoot "config\k8s\rabbitmq\rabbitmq-external.yaml"
if (Test-Path $RabbitExternal) {
    Write-Host "Applying rabbitmq-external NodePort..."
    kubectl apply -f $RabbitExternal
}

foreach ($deploy in @("backend", "frontend", "ai-fastapi")) {
    Write-Host "Waiting for deployment/$deploy..."
    kubectl wait --for=condition=available `
        "deployment/$deploy" `
        -n $Namespace `
        --timeout=$timeout
}

Write-Host "Fabric health via backend pod..."
$maxAttempts = 30
for ($i = 1; $i -le $maxAttempts; $i++) {
    kubectl exec -n $Namespace deploy/backend -- curl -sf $FabricHealthUrl 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Fabric Gateway reachable from EKS (backend pod)." -ForegroundColor Green
        exit 0
    }

    $jobName = "fabric-health-$([guid]::NewGuid().ToString().Substring(0, 8))"
    kubectl run $jobName `
        --rm -i --restart=Never `
        --image=curlimages/curl:8.5.0 `
        -n $Namespace `
        --command -- curl -sf $FabricHealthUrl 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Fabric Gateway reachable from EKS (curl pod)." -ForegroundColor Green
        exit 0
    }

    Write-Host "  attempt $i/$maxAttempts..."
    Start-Sleep -Seconds 15
}

throw "Fabric health check failed: $FabricHealthUrl"
