param(
    [Parameter(Mandatory = $true)][string]$ClusterName,
    [string]$Region = "ap-northeast-2",
    [Parameter(Mandatory = $true)][string]$RepoUrl,
    [string]$TargetRevision = "master",
    [string]$AppPath = "config/k8s"
)

$ErrorActionPreference = "Stop"

$manifest = @"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: forenshield
  namespace: argocd
spec:
  project: default
  source:
    repoURL: $RepoUrl
    targetRevision: $TargetRevision
    path: $AppPath
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: forenshield
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
"@

$tmp = New-TemporaryFile
[System.IO.File]::WriteAllText($tmp.FullName, $manifest)

aws eks update-kubeconfig --name $ClusterName --region $Region | Out-Null
kubectl apply -f $tmp.FullName
Remove-Item $tmp.FullName
Write-Host "Argo CD Application applied." -ForegroundColor Green
