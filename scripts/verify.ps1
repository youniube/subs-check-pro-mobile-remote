[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$workspace = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $workspace 'runtime\bin\subs-check-pro.exe'
$config = Join-Path $workspace 'runtime\config\config.yaml'
$customCore = Join-Path $workspace 'runtime\bin\subs-check-pro-custom-v2.6.7.exe'
$officialCore = Join-Path $workspace 'runtime\bin\subs-check-pro-official-v2.6.7.exe'
$renamePatch = Join-Path $workspace 'patches\subs-check-pro-v2.6.7-custom-rename.patch'
$failures = New-Object System.Collections.Generic.List[string]

function Test-RequiredPath {
    param([string]$Path, [string]$Label)
    if (Test-Path -LiteralPath $Path) {
        Write-Output "[OK] $Label"
    } else {
        Write-Output "[FAIL] $Label"
        $failures.Add($Label)
    }
}

Test-RequiredPath -Path $exe -Label 'Executable exists'
Test-RequiredPath -Path $config -Label 'Config exists'
Test-RequiredPath -Path $customCore -Label 'Custom rename core exists'
Test-RequiredPath -Path $officialCore -Label 'Official v2.6.7 core backup exists'
Test-RequiredPath -Path $renamePatch -Label 'Custom rename patch exists'

try {
    $currentHash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
    $customHash = (Get-FileHash -LiteralPath $customCore -Algorithm SHA256).Hash
    if ($currentHash -ne $customHash) {
        throw 'active executable does not match the custom rename core'
    }

    $renameConfig = [IO.File]::ReadAllText($config)
    foreach ($required in @(
        '(?m)^rename-node:\s*true\s*$',
        '(?m)^update:\s*false\s*$',
        '(?m)^update-on-startup:\s*false\s*$'
    )) {
        if (-not [regex]::IsMatch($renameConfig, $required)) {
            throw "required config is missing: $required"
        }
    }
    Write-Output '[OK] Custom rename core and overwrite protection are active'
} catch {
    Write-Output "[FAIL] Custom rename verification failed: $($_.Exception.Message)"
    $failures.Add('Custom rename core')
}

$listeners = netstat -ano
if ($listeners | Select-String -Pattern '^\s*TCP\s+127\.0\.0\.1:8199\s+[^\s]+\s+LISTENING\s+\d+\s*$') {
    Write-Output '[OK] WebUI listens only on 127.0.0.1:8199'
} else {
    Write-Output '[FAIL] WebUI does not listen on 127.0.0.1:8199'
    $failures.Add('127.0.0.1:8199')
}

if ($listeners | Select-String -Pattern '^\s*TCP\s+127\.0\.0\.1:7890\s+[^\s]+\s+LISTENING\s+\d+\s*$') {
    Write-Output '[OK] Sparkle/Mihomo remains on 127.0.0.1:7890'
} else {
    Write-Output '[WARN] Sparkle/Mihomo listener was not detected'
}

try {
    $webRequestParams = @{
        Uri             = 'http://127.0.0.1:8199/admin'
        UseBasicParsing = $true
        TimeoutSec      = 8
    }
    $response = Invoke-WebRequest @webRequestParams
    if ($response.StatusCode -eq 200) {
        Write-Output '[OK] Local WebUI returned HTTP 200'
    } else {
        throw "HTTP $($response.StatusCode)"
    }
} catch {
    Write-Output "[FAIL] Local WebUI request failed: $($_.Exception.Message)"
    $failures.Add('WebUI HTTP')
}

try {
    Add-Type -AssemblyName System.Net.Http
    $configText = [IO.File]::ReadAllText($config)
    $keyMatch = [regex]::Match($configText, '(?m)^\s*api-key:\s*"([^"]+)"')
    if (-not $keyMatch.Success) {
        throw 'API key is missing from config.yaml'
    }
    $apiKey = $keyMatch.Groups[1].Value

    function Get-DirectHttpStatus {
        param(
            [string]$Uri,
            [string]$ApiKey
        )

        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.UseProxy = $false
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromSeconds(10)
        $request = $null
        try {
            $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $Uri)
            if ($ApiKey) {
                [void]$request.Headers.TryAddWithoutValidation('X-API-Key', $ApiKey)
            }
            $response = $client.SendAsync($request).GetAwaiter().GetResult()
            try {
                return [int]$response.StatusCode
            } finally {
                $response.Dispose()
            }
        } finally {
            if ($null -ne $request) { $request.Dispose() }
            $client.Dispose()
            $handler.Dispose()
        }
    }

    $publicAdmin = Get-DirectHttpStatus -Uri 'https://cesusub.sbxm.eu.org/admin'
    $publicWithoutKey = Get-DirectHttpStatus -Uri 'https://cesusub.sbxm.eu.org/api/status'
    $publicWithKey = Get-DirectHttpStatus -Uri 'https://cesusub.sbxm.eu.org/api/status' -ApiKey $apiKey
    if ($publicAdmin -eq 200 -and $publicWithoutKey -eq 401 -and $publicWithKey -eq 200) {
        Write-Output '[OK] Public HTTPS route and API-key enforcement passed'
    } else {
        throw "Unexpected statuses: admin=$publicAdmin, no-key=$publicWithoutKey, with-key=$publicWithKey"
    }

    $leakingLogs = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath (Join-Path $workspace 'runtime\logs') -Filter 'subs-check-pro-*.log' -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            $stream = [IO.File]::Open($_.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try {
                $reader = New-Object IO.StreamReader($stream, (New-Object Text.UTF8Encoding($false)), $true)
                try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
            } finally {
                $stream.Dispose()
            }
            if ($content.Contains($apiKey)) {
                $leakingLogs.Add($_.Name)
            }
        }
    if ($leakingLogs.Count -eq 0) {
        Write-Output '[OK] API key is absent from retained logs'
    } else {
        throw "API key appears in $($leakingLogs.Count) retained log file(s)"
    }
} catch {
    Write-Output "[FAIL] Public/security verification failed: $($_.Exception.Message)"
    $failures.Add('Public/security verification')
}

$runValue = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'SubsCheckProMobile' -ErrorAction SilentlyContinue).SubsCheckProMobile
if ($runValue) {
    Write-Output '[OK] Current-user auto-start exists'
} else {
    Write-Output '[WARN] Current-user auto-start is missing'
}

$cloudflared = Get-Process -Name 'cloudflared' -ErrorAction SilentlyContinue
if ($cloudflared) {
    Write-Output '[OK] Cloudflare Tunnel process is running'
} else {
    Write-Output '[FAIL] Cloudflare Tunnel process is not running'
    $failures.Add('cloudflared process')
}

Write-Output 'Phone URL: https://cesusub.sbxm.eu.org/admin'

if ($failures.Count -gt 0) {
    Write-Output ("Failed checks: " + ($failures -join ', '))
    exit 1
}

Write-Output 'Local core verification passed.'
