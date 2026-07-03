# Park Phase 1 전: ALB Ingress finalizer 때문에 Terminating 에 걸리는 것 방지
param(
    [string]$ClusterName = "forenshield",
    [string]$Region = "ap-northeast-2"
)

$ErrorActionPreference = "Continue"

$clusterStatus = aws eks describe-cluster --name $ClusterName --region $Region --query "cluster.status" --output text 2>$null
if ($LASTEXITCODE -ne 0 -or -not $clusterStatus) {
    Write-Host "Cluster '$ClusterName' 없음 — k8s cleanup 생략."
    exit 0
}

Write-Host "=== Park k8s cleanup (cluster=$ClusterName) ===" -ForegroundColor Cyan
aws eks update-kubeconfig --name $ClusterName --region $Region | Out-Null

# Argo CD Application 이 남아 있으면 destroy 중 Ingress 를 다시 만들어 namespace 가 Terminating 에 걸림
$argoApps = kubectl get applications.argoproj.io -n argocd -o jsonpath='{.items[*].metadata.name}' 2>$null
if ($argoApps) {
    foreach ($app in ($argoApps -split '\s+')) {
        if (-not $app) { continue }
        Write-Host "Argo CD Application 삭제: $app"
        kubectl patch application $app -n argocd -p '{"metadata":{"finalizers":null}}' --type=merge 2>$null
        kubectl delete application $app -n argocd --ignore-not-found --wait=false 2>$null
    }
    Start-Sleep -Seconds 5
}

# ALB controller Pod 가 Pending 이면 webhook 이 막혀 finalizer patch 가 실패함
$webhookEndpoints = kubectl get endpoints aws-load-balancer-webhook-service -n kube-system -o jsonpath='{.subsets[*].addresses[*].ip}' 2>$null
if (-not $webhookEndpoints) {
    Write-Host "ALB webhook 비활성 — validating webhook 제거 (Park 전용)"
    kubectl delete validatingwebhookconfiguration aws-load-balancer-webhook --ignore-not-found 2>$null
}

function Clear-Ingress {
    param([string]$Name, [string]$Namespace)

    $found = kubectl get ingress $Name -n $Namespace --ignore-not-found -o name 2>$null
    if (-not $found) { return }

    Write-Host "Ingress 정리: $Namespace/$Name"
    kubectl patch ingress $Name -n $Namespace -p '{"metadata":{"finalizers":[]}}' --type=merge 2>$null
    kubectl delete ingress $Name -n $Namespace --wait=false --ignore-not-found 2>$null

    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        $still = kubectl get ingress $Name -n $Namespace --ignore-not-found -o name 2>$null
        if (-not $still) { return }

        # Terminating 상태면 finalizer 강제 제거 후 replace
        $json = kubectl get ingress $Name -n $Namespace -o json 2>$null
        if ($json) {
            $obj = $json | ConvertFrom-Json
            if ($obj.metadata.finalizers -and $obj.metadata.finalizers.Count -gt 0) {
                $obj.metadata.finalizers = @()
                $obj | ConvertTo-Json -Depth 20 -Compress | kubectl replace -f - 2>$null
            }
        }
        Start-Sleep -Seconds 3
    }
    Write-Warning "Ingress $Namespace/$Name 가 아직 남아 있습니다 — terraform state rm 으로 우회합니다."
}

function Clear-AllIngresses {
    param([string]$Namespace)

    $names = kubectl get ingress -n $Namespace -o jsonpath='{.items[*].metadata.name}' 2>$null
    if (-not $names) { return }
    foreach ($name in ($names -split '\s+')) {
        if ($name) { Clear-Ingress -Name $name -Namespace $Namespace }
    }
}

function Clear-Namespace {
    param([string]$Name)

    $phase = kubectl get namespace $Name -o jsonpath='{.status.phase}' 2>$null
    if (-not $phase) { return }

    Write-Host "Namespace 정리: $Name (phase=$phase)"
    Clear-AllIngresses -Namespace $Name

    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        $phase = kubectl get namespace $Name -o jsonpath='{.status.phase}' 2>$null
        if (-not $phase) { return }
        if ($phase -ne "Terminating") {
            kubectl delete namespace $Name --ignore-not-found --wait=false 2>$null
            Start-Sleep -Seconds 3
            continue
        }

        $json = kubectl get namespace $Name -o json 2>$null
        if ($json) {
            $obj = $json | ConvertFrom-Json
            if ($obj.spec.finalizers -and $obj.spec.finalizers.Count -gt 0) {
                $obj.spec.finalizers = @()
                $obj | ConvertTo-Json -Depth 10 -Compress | kubectl replace --raw "/api/v1/namespaces/$Name/finalize" -f - 2>$null
            }
        }
        Start-Sleep -Seconds 3
        $still = kubectl get namespace $Name --ignore-not-found -o name 2>$null
        if (-not $still) { return }
    }
    Write-Warning "Namespace $Name 가 아직 남아 있습니다 — terraform state rm 으로 우회합니다."
}

Clear-AllIngresses -Namespace "forenshield"
Clear-AllIngresses -Namespace "argocd"
Clear-Namespace -Name "forenshield"

foreach ($albName in @("forenshield-k8s-app", "forenshield-k8s-argocd")) {
    $arn = aws elbv2 describe-load-balancers --names $albName --region $Region --query "LoadBalancers[0].LoadBalancerArn" --output text 2>$null
    if ($arn -and $arn -ne "None") {
        Write-Host "고아 ALB 삭제: $albName"
        aws elbv2 delete-load-balancer --load-balancer-arn $arn --region $Region 2>$null
    }
}

Start-Sleep -Seconds 3
Write-Host "k8s cleanup 완료." -ForegroundColor Green
