[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$workspace = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $workspace 'runtime\bin\subs-check-pro.exe'
$config = Join-Path $workspace 'runtime\config\config.yaml'
$customCore = Join-Path $workspace 'runtime\bin\subs-check-pro-custom-v2.6.8.exe'
$officialCore = Join-Path $workspace 'runtime\bin\subs-check-pro-official-v2.6.8.exe'
$renamePatch = Join-Path $workspace 'patches\subs-check-pro-v2.6.8-custom-rename.patch'
$analysisPatch = Join-Path $workspace 'patches\subs-check-pro-v2.6.8-analysis-report.patch'
$webuiAnalysisPatch = Join-Path $workspace 'patches\subs-check-pro-webui-b8db5f51c367-analysis-report.patch'
$historyPatch = Join-Path $workspace 'patches\subs-check-pro-v2.6.8-subscription-history.patch'
$webuiHistoryPatch = Join-Path $workspace 'patches\subs-check-pro-webui-b8db5f51c367-subscription-history.patch'
$uaFallbackPatch = Join-Path $workspace 'patches\subs-check-pro-v2.6.8-ua-fallback.patch'
$loopbackHistoryPatch = Join-Path $workspace 'patches\subs-check-pro-v2.6.8-loopback-history.patch'
$cleanInternalTagsPatch = Join-Path $workspace 'patches\subs-check-pro-v2.6.8-clean-internal-tags.patch'
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
Test-RequiredPath -Path $officialCore -Label 'Official v2.6.8 core backup exists'
Test-RequiredPath -Path $renamePatch -Label 'Custom rename patch exists'
Test-RequiredPath -Path $analysisPatch -Label 'Analysis report core patch exists'
Test-RequiredPath -Path $webuiAnalysisPatch -Label 'Analysis report WebUI patch exists'
Test-RequiredPath -Path $historyPatch -Label 'Subscription history core patch exists'
Test-RequiredPath -Path $webuiHistoryPatch -Label 'Subscription history WebUI patch exists'
Test-RequiredPath -Path $uaFallbackPatch -Label 'Subscription UA fallback patch exists'
Test-RequiredPath -Path $loopbackHistoryPatch -Label 'Loopback history replay patch exists'
Test-RequiredPath -Path $cleanInternalTagsPatch -Label 'Internal source tag cleanup patch exists'

try {
    $uaPatchText = [IO.File]::ReadAllText($uaFallbackPatch)
    foreach ($signature in @(
        'structuralValidHits',
        'if structuralHits == 0',
        'if retryStructuralHits > 0',
        'TestProcessSubscriptionRetriesClientUAAfterOnlyMalformedCandidates',
        'TestProcessSubscriptionDoesNotRetryStructurallyValidFilteredResponse'
    )) {
        if (-not $uaPatchText.Contains($signature)) {
            throw "UA fallback v2 signature is missing: $signature"
        }
    }
    Write-Output '[OK] Subscription UA fallback uses structurally valid nodes'
} catch {
    Write-Output "[FAIL] Subscription UA fallback verification failed: $($_.Exception.Message)"
    $failures.Add('Subscription UA fallback v2')
}

try {
    $loopbackPatchText = [IO.File]::ReadAllText($loopbackHistoryPatch)
    foreach ($signature in @(
        'normalizeListenPort',
        'net.SplitHostPort',
        'localSubscriptionURL',
        'http://127.0.0.1:8199/all.yaml',
        'http://127.0.0.1:8199/history.yaml',
        'TestIdentifyLocalSubTypeWithQualifiedConfiguredPort'
    )) {
        if (-not $loopbackPatchText.Contains($signature)) {
            throw "Loopback history signature is missing: $signature"
        }
    }
    Write-Output '[OK] Loopback success/history replay uses normalized ports'
} catch {
    Write-Output "[FAIL] Loopback history verification failed: $($_.Exception.Message)"
    $failures.Add('Loopback history replay')
}

try {
    $cleanTagsPatchText = [IO.File]::ReadAllText($cleanInternalTagsPatch)
    foreach ($signature in @(
        'if isLatest || isHistory',
        'tag = ""',
        'ordinary subscription tag',
        'wantTag:  "Custom"'
    )) {
        if (-not $cleanTagsPatchText.Contains($signature)) {
            throw "Internal tag cleanup signature is missing: $signature"
        }
    }
    Write-Output '[OK] Internal Succeed/History tags are excluded from exported names'
} catch {
    Write-Output "[FAIL] Internal tag cleanup verification failed: $($_.Exception.Message)"
    $failures.Add('Internal source tag cleanup')
}

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

if ($listeners | Select-String -Pattern '^\s*TCP\s+127\.0\.0\.1:8299\s+[^\s]+\s+LISTENING\s+\d+\s*$') {
    Write-Output '[OK] Sub-Store listens only on 127.0.0.1:8299'
} else {
    Write-Output '[FAIL] Sub-Store does not listen on 127.0.0.1:8299'
    $failures.Add('127.0.0.1:8299')
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
    $analysisPage = Invoke-WebRequest -UseBasicParsing `
        -Uri 'http://127.0.0.1:8199/analysis' `
        -TimeoutSec 8
    if (-not $analysisPage.Content.Contains('/static/js/analysis.js?v20260720-sub-history') -or
        -not $analysisPage.Content.Contains('/static/css/analysis.css?v20260720-sub-history')) {
        throw 'analysis page cache-busting version is missing'
    }
    $analysisScript = Invoke-WebRequest -UseBasicParsing `
        -Uri 'http://127.0.0.1:8199/static/js/analysis.js?v20260720-sub-history' `
        -TimeoutSec 8
    $hasAnalysisToggle = $analysisScript.Content.Contains('toggleIncludeBad(this.checked)')
    $hasCombinedCount = $analysisScript.Content.Contains('setBadVisibility(include && silentCount > 0)')
    $hasHistoryTrend = $analysisScript.Content.Contains('consecutive_silent')
    $hasDeleteSuggestion = $analysisScript.Content.Contains('delete_suggested')
    if (-not ($hasAnalysisToggle -and $hasCombinedCount -and $hasHistoryTrend -and $hasDeleteSuggestion)) {
        throw 'active WebUI does not contain the analysis report history fix'
    }
    Write-Output '[OK] Analysis report interaction and cross-run history are active'
} catch {
    Write-Output "[FAIL] Analysis report WebUI verification failed: $($_.Exception.Message)"
    $failures.Add('Analysis report WebUI')
}

$analysisReport = Join-Path $workspace 'runtime\output\stats\subs-analysis.yaml'
$historyReport = Join-Path $workspace 'runtime\output\stats\subs-health-history.yaml'
if (Test-Path -LiteralPath $analysisReport -PathType Leaf) {
    $analysisReportText = [IO.File]::ReadAllText($analysisReport)
    $activeBlock = [regex]::Match(
        $analysisReportText,
        '(?ms)^subs_ranking:\s*(.*?)^subs_ranking_bad:'
    )
    if ($activeBlock.Success) {
        $totals = [regex]::Matches($activeBlock.Groups[1].Value, 'total:\s*(\d+)')
        $positiveTotals = @($totals | Where-Object { [int]$_.Groups[1].Value -gt 0 })
        if ($totals.Count -gt 0 -and $positiveTotals.Count -eq 0) {
            Write-Output '[WARN] Existing analysis report predates the fix; run one new detection to regenerate it'
        } else {
            Write-Output '[OK] Existing analysis report contains subscription totals'
        }
    }
}

if (Test-Path -LiteralPath $historyReport -PathType Leaf) {
    $historyText = [IO.File]::ReadAllText($historyReport)
    if ($historyText -match '(?m)^version:\s*1\s*$' -and
        $historyText -match '(?m)^completed_runs:\s*\d+\s*$' -and
        $historyText -match '(?m)^subscriptions:\s*$') {
        Write-Output '[OK] Subscription health history is persisted'
    } else {
        Write-Output '[FAIL] Subscription health history file is malformed'
        $failures.Add('Subscription health history')
    }
} else {
    Write-Output '[WARN] Subscription health history will start after the next completed detection'
}

try {
    $versionInfo = Invoke-RestMethod -UseBasicParsing `
        -Uri 'http://127.0.0.1:8199/admin/version' -TimeoutSec 8
    if ($versionInfo.version -ne 'v2.6.8+custom.history.ua2.loopback1.cleantags1') {
        throw "Unexpected active version: $($versionInfo.version)"
    }
    Write-Output '[OK] Active version uses non-prerelease custom metadata'
    if ($versionInfo.latest_version) {
        Write-Output "[WARN] Upstream release available: $($versionInfo.latest_version)"
    } else {
        Write-Output '[OK] Version API has no NEW badge state'
    }
} catch {
    Write-Output "[FAIL] Version metadata verification failed: $($_.Exception.Message)"
    $failures.Add('Version metadata')
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
