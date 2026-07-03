# Public HTTPS health check — Route53/ALB 전파 후
param(
    [Parameter(Mandatory = $true)]
    [string]$Url,
    [int]$MaxAttempts = 36,
    [int]$SleepSeconds = 10
)

$ErrorActionPreference = "Stop"

Write-Host "=== Health check: $Url ===" -ForegroundColor Cyan

for ($i = 1; $i -le $MaxAttempts; $i++) {
    try {
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            curl.exe -sf -o NUL -w "%{http_code}" $Url | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Health OK ($Url)" -ForegroundColor Green
                exit 0
            }
        }
        else {
            # PowerShell 5.1 fallback
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 20
            if ($response.StatusCode -eq 200) {
                Write-Host "Health OK ($Url)" -ForegroundColor Green
                exit 0
            }
            Write-Host "  attempt $i/$MaxAttempts — status $($response.StatusCode)"
        }
    }
    catch {
        Write-Host "  attempt $i/$MaxAttempts — $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $SleepSeconds
}

throw "Health check failed after $MaxAttempts attempts: $Url"
