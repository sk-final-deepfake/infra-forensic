# Ingress ALB hostname 대기 후 Route53 UPSERT
param(
    [Parameter(Mandatory = $true)][string]$ClusterName,
    [string]$Region = "ap-northeast-2",
    [Parameter(Mandatory = $true)][string]$ZoneId,
    [Parameter(Mandatory = $true)][string]$AppDomain,
    [Parameter(Mandatory = $true)][string]$ArgocdDomain,
    [string]$AlbZoneId = "ZWKZPGTI48KDX",
    [int]$TimeoutSeconds = 900
)

$ErrorActionPreference = "Stop"

function Wait-IngressHostname {
    param([string]$Name, [string]$Namespace)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $albHost = kubectl get ingress $Name -n $Namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
        if ($albHost) { return $albHost.Trim() }
        Start-Sleep -Seconds 15
    }
    throw "Ingress $Namespace/$Name hostname not ready"
}

function Upsert-AliasRecord {
    param([string]$Name, [string]$TargetHost)
    $dnsName = if ($TargetHost.StartsWith("dualstack.")) { $TargetHost } else { $TargetHost }
    $change = @{
        Changes = @(@{
            Action = "UPSERT"
            ResourceRecordSet = @{
                Name = $Name
                Type = "A"
                AliasTarget = @{
                    HostedZoneId         = $AlbZoneId
                    DNSName              = $dnsName
                    EvaluateTargetHealth = $true
                }
            }
        })
    } | ConvertTo-Json -Depth 6 -Compress

    $tmp = New-TemporaryFile
    [System.IO.File]::WriteAllText($tmp.FullName, $change)
    aws route53 change-resource-record-sets --hosted-zone-id $ZoneId --change-batch "file://$($tmp.FullName)" --region $Region | Out-Null
    Remove-Item $tmp.FullName -Force
    Write-Host "Route53 UPSERT: $Name -> $dnsName" -ForegroundColor Green
}

Write-Host "=== Route53 UPSERT ===" -ForegroundColor Cyan
aws eks update-kubeconfig --name $ClusterName --region $Region | Out-Null

$appHost = Wait-IngressHostname -Name "forenshield-ingress" -Namespace "forenshield"
$argocdHost = Wait-IngressHostname -Name "argocd-ingress" -Namespace "argocd"

Upsert-AliasRecord -Name $AppDomain -TargetHost $appHost
Upsert-AliasRecord -Name $ArgocdDomain -TargetHost $argocdHost

Write-Host "Route53 done." -ForegroundColor Green
