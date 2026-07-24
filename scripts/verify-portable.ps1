[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$workspace = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $workspace 'runtime'
$config = Join-Path $runtime 'config\config.yaml'
$cloudflaredConfig = Join-Path $runtime 'cloudflared\config.yml'
$credentials = Join-Path $runtime 'cloudflared\credentials.json'
$failures = New-Object System.Collections.Generic.List[string]

function Add-Check {
    param(
        [bool]$Passed,
        [string]$Label
    )

    if ($Passed) {
        Write-Output "[OK] $Label"
    } else {
        Write-Output "[FAIL] $Label"
        $failures.Add($Label)
    }
}

$core = Join-Path $runtime 'bin\subs-check-pro.exe'
$cloudflared = Join-Path $runtime 'bin\cloudflared.exe'
Add-Check -Passed (Test-Path -LiteralPath $core -PathType Leaf) -Label 'Patched core exists'
Add-Check -Passed (Test-Path -LiteralPath $cloudflared -PathType Leaf) -Label 'cloudflared exists'
Add-Check -Passed (Test-Path -LiteralPath $config -PathType Leaf) -Label 'Local configuration exists'

if (Test-Path -LiteralPath $config -PathType Leaf) {
    $configText = [IO.File]::ReadAllText($config)
    Add-Check -Passed (
        -not [regex]::IsMatch($configText, '(?m)^(?!\s*#).*CHANGE_ME')
    ) -Label 'Configuration placeholders are replaced'
    Add-Check -Passed ($configText -match '(?m)^listen-port:\s*"127\.0\.0\.1:8199"\s*$') `
        -Label 'WebUI is restricted to IPv4 loopback'
    Add-Check -Passed ($configText -match '(?m)^system-proxy:\s*"direct"\s*$') `
        -Label 'Core remains independent from the Windows proxy'
}

$listeners = netstat -ano
$webListening = [bool]($listeners | Select-String `
    -Pattern '^\s*TCP\s+127\.0\.0\.1:8199\s+[^\s]+\s+LISTENING\s+\d+\s*$')
$subStoreListening = [bool]($listeners | Select-String `
    -Pattern '^\s*TCP\s+127\.0\.0\.1:8299\s+[^\s]+\s+LISTENING\s+\d+\s*$')
Add-Check -Passed $webListening -Label 'WebUI listens on 127.0.0.1:8199'
Add-Check -Passed $subStoreListening -Label 'Sub-Store listens on 127.0.0.1:8299'

if ($webListening) {
    try {
        $version = Invoke-RestMethod -UseBasicParsing `
            -Uri 'http://127.0.0.1:8199/admin/version' -TimeoutSec 8
        Add-Check -Passed ($version.version -like 'v2.6.8+custom.*') `
            -Label 'Patched core version is active'
    } catch {
        Add-Check -Passed $false -Label 'Local WebUI version API is reachable'
    }
}

$tunnelExpected = (Test-Path -LiteralPath $cloudflaredConfig -PathType Leaf) -or
    (Test-Path -LiteralPath $credentials -PathType Leaf)
if ($tunnelExpected) {
    Add-Check -Passed (
        (Test-Path -LiteralPath $cloudflaredConfig -PathType Leaf) -and
        (Test-Path -LiteralPath $credentials -PathType Leaf)
    ) -Label 'Tunnel configuration and credentials are both present'
    $tunnelProcess = Get-Process -Name 'cloudflared' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq $cloudflared }
    Add-Check -Passed ([bool]$tunnelProcess) -Label 'Cloudflare Tunnel process is running'
} else {
    Write-Output '[INFO] Tunnel is not configured; local-only mode is valid.'
}

if ($failures.Count -gt 0) {
    Write-Output ('Failed checks: ' + ($failures -join ', '))
    exit 1
}

Write-Output 'Portable installation checks passed.'
