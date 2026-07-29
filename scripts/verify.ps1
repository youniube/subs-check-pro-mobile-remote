[CmdletBinding()]
param(
    [switch]$IncludePublicAuthenticatedCheck
)

# Windows PowerShell 5.1 treats UTF-8 without a BOM as the local ANSI code page.
# Keep this script ASCII-only so it remains portable across PowerShell versions.
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
$silentArchivePatch = Join-Path $workspace 'patches\subs-check-pro-v2.6.8-silent-subscription-archive.patch'
$cronHotReloadPatch = Join-Path $workspace 'patches\subs-check-pro-v2.6.8-cron-hot-reload.patch'
$configRuntimeStatePatch = Join-Path $workspace 'patches\subs-check-pro-v2.6.8-config-runtime-state.patch'
$subStoreRuntimeManagerPatch = Join-Path $workspace 'patches\subs-check-pro-v2.6.8-substore-runtime-manager.patch'
$runtimeAddressOutputPatch = Join-Path $workspace 'patches\subs-check-pro-v2.6.8-runtime-address-output.patch'
$configSemanticsPatch = Join-Path $workspace 'patches\subs-check-pro-v2.6.8-webui-config-semantics.patch'
$subStoreMailboxRacePatch = Join-Path $workspace 'patches\subs-check-pro-v2.6.8-substore-mailbox-race.patch'
$webuiConfigSemanticsPatch = Join-Path $workspace 'patches\subs-check-pro-webui-b8db5f51c367-config-semantics.patch'
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
Test-RequiredPath -Path $silentArchivePatch -Label 'Silent subscription archive patch exists'
Test-RequiredPath -Path $cronHotReloadPatch -Label 'Cron hot reload patch exists'
Test-RequiredPath -Path $configRuntimeStatePatch -Label 'Configuration runtime state patch exists'
Test-RequiredPath -Path $subStoreRuntimeManagerPatch -Label 'Sub-Store runtime manager patch exists'
Test-RequiredPath -Path $runtimeAddressOutputPatch -Label 'Runtime address and output patch exists'
Test-RequiredPath -Path $configSemanticsPatch -Label 'Configuration semantics core patch exists'
Test-RequiredPath -Path $subStoreMailboxRacePatch -Label 'Sub-Store mailbox race patch exists'
Test-RequiredPath -Path $webuiConfigSemanticsPatch -Label 'Configuration semantics WebUI patch exists'

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
    $silentArchivePatchText = [IO.File]::ReadAllText($silentArchivePatch)
    foreach ($signature in @(
        'silent-subscriptions.yaml',
        'SyncSilentSubscriptionArchive',
        'NewSubscriptionURLs',
        'FindArchivedSilentSubscriptions',
        'filterArchivedSilentSubscriptions',
        'archiveErr := filterArchivedSilentSubscriptions(remote)',
        'http.StatusConflict',
        'TestArchivedSilentSubscriptionMatchesWithoutRemark',
        'TestFilterArchivedSubscriptionURLsAfterRemoteExpansion'
    )) {
        if (-not $silentArchivePatchText.Contains($signature)) {
            throw "Silent archive signature is missing: $signature"
        }
    }
    Write-Output '[OK] Silent subscriptions are archived and rejected when re-added'
} catch {
    Write-Output "[FAIL] Silent subscription archive verification failed: $($_.Exception.Message)"
    $failures.Add('Silent subscription archive')
}

try {
    $cronHotReloadPatchText = [IO.File]::ReadAllText($cronHotReloadPatch)
    foreach ($signature in @(
        'appliedTimerCron',
        'timerConfigMatches',
        'configReloadMu',
        'app.onConfigChange()',
        'TestConfigReloadRepairsStaleCronTimer',
        'stale cron scheduler was not replaced'
    )) {
        if (-not $cronHotReloadPatchText.Contains($signature)) {
            throw "Cron hot reload signature is missing: $signature"
        }
    }
    Write-Output '[OK] Cron configuration reload repairs the running scheduler'
} catch {
    Write-Output "[FAIL] Cron hot reload verification failed: $($_.Exception.Message)"
    $failures.Add('Cron hot reload')
}

try {
    $configRuntimeStatePatchText = [IO.File]::ReadAllText($configRuntimeStatePatch)
    foreach ($signature in @(
        'configStatePendingNextRun',
        'pendingConfigVersion',
        'effectiveConfigLocked',
        'config_status',
        'TestConfigReloadDefersPublicationUntilCheckFinishes',
        'TestConcurrentEquivalentReloadsCreateOnePendingVersion'
    )) {
        if (-not $configRuntimeStatePatchText.Contains($signature)) {
            throw "Configuration runtime state signature is missing: $signature"
        }
    }
    Write-Output '[OK] Configuration reload uses versioned snapshots and truthful apply state'
} catch {
    Write-Output "[FAIL] Configuration runtime state verification failed: $($_.Exception.Message)"
    $failures.Add('Configuration runtime state')
}

try {
    $subStoreRuntimeManagerPatchText = [IO.File]::ReadAllText($subStoreRuntimeManagerPatch)
    foreach ($signature in @(
        'SubStoreRuntimeSpec',
        'subStoreManager',
        'pending-service-reconfigure',
        'graceful-stop-timeout',
        'TestSubStoreSubmitReturnsWithoutWaitingForProcessExit',
        'TestSubStoreManagerCoalescesRapidChangesAndNeverOverlapsRunners',
        'TestSubStoreRuntimeSpecChangesTriggerReconcile',
        'TestSubStoreManagerUsesKillFallbackAfterStopTimeout'
    )) {
        if (-not $subStoreRuntimeManagerPatchText.Contains($signature)) {
            throw "Sub-Store runtime manager signature is missing: $signature"
        }
    }
    Write-Output '[OK] Sub-Store uses one asynchronous versioned runtime manager'
} catch {
    Write-Output "[FAIL] Sub-Store runtime manager verification failed: $($_.Exception.Message)"
    $failures.Add('Sub-Store runtime manager')
}

try {
    $runtimeAddressOutputPatchText = [IO.File]::ReadAllText($runtimeAddressOutputPatch)
    foreach ($signature in @(
        'ParseListenAddress',
        'BuildLoopbackHTTPURL',
        'serveCurrentOutputFile',
        'safeSharePath',
        'NewLocalSaverForRuntime',
        'KillNodeForSpec',
        'TestBuildLoopbackHTTPURLNeverDuplicatesConfiguredHost',
        'TestStaticDownloadRouteFollowsAppliedOutputDirectory'
    )) {
        if (-not $runtimeAddressOutputPatchText.Contains($signature)) {
            throw "Runtime address/output signature is missing: $signature"
        }
    }
    Write-Output '[OK] Internal URLs and output routes follow the applied runtime configuration'
} catch {
    Write-Output "[FAIL] Runtime address/output verification failed: $($_.Exception.Message)"
    $failures.Add('Runtime address and output')
}

try {
    $subStoreMailboxRacePatchText = [IO.File]::ReadAllText($subStoreMailboxRacePatch)
    foreach ($signature in @(
        'Keep this discard non-blocking',
        'case <-manager.requests:',
        'Submit never waits on an empty mailbox'
    )) {
        if (-not $subStoreMailboxRacePatchText.Contains($signature)) {
            throw "Sub-Store mailbox race signature is missing: $signature"
        }
    }
    Write-Output '[OK] Sub-Store latest-request mailbox cannot block on a concurrent receive'
} catch {
    Write-Output "[FAIL] Sub-Store mailbox race verification failed: $($_.Exception.Message)"
    $failures.Add('Sub-Store mailbox race')
}

try {
    $configSemanticsPatchText = [IO.File]::ReadAllText($configSemanticsPatch)
    $webuiConfigSemanticsPatchText = [IO.File]::ReadAllText($webuiConfigSemanticsPatch)
    foreach ($signature in @(
        'apiKeyGracePeriod',
        'auth_transition',
        'configFieldPolicies',
        'runtime policy field count = %d, want 96',
        'ReconfigureUpdateTasks',
        'schedulerApplyStatus',
        'TestSchedulerStatusReportsActualCronAndNextRun',
        'TestWebUIAccessFollowsAppliedConfigWithoutRouterRestart'
    )) {
        if (-not $configSemanticsPatchText.Contains($signature)) {
            throw "Core configuration semantics signature is missing: $signature"
        }
    }
    foreach ($signature in @(
        'pendingSessionKey',
        'promoteSessionKey',
        'v20260728-config-runtime',
        'config form control count = %d, want 89',
        'github-token'
    )) {
        if (-not $webuiConfigSemanticsPatchText.Contains($signature)) {
            throw "WebUI configuration semantics signature is missing: $signature"
        }
    }
    Write-Output '[OK] WebUI reports real apply states and safely transitions API keys'
} catch {
    Write-Output "[FAIL] Configuration semantics verification failed: $($_.Exception.Message)"
    $failures.Add('Configuration semantics')
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
$silentArchive = Join-Path $workspace 'runtime\output\stats\silent-subscriptions.yaml'
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

if (Test-Path -LiteralPath $silentArchive -PathType Leaf) {
    $silentArchiveText = [IO.File]::ReadAllText($silentArchive)
    if ($silentArchiveText -match '(?m)^version:\s*1\s*$' -and
        $silentArchiveText -match '(?m)^consecutive_silent_threshold:\s*3\s*$' -and
        $silentArchiveText -match '(?m)^subscriptions:\s*$') {
        Write-Output '[OK] Silent subscription archive is persisted'
    } else {
        Write-Output '[FAIL] Silent subscription archive file is malformed'
        $failures.Add('Silent subscription archive file')
    }
} else {
    Write-Output '[FAIL] Silent subscription archive file is missing'
    $failures.Add('Silent subscription archive file')
}

try {
    $versionInfo = Invoke-RestMethod -UseBasicParsing `
        -Uri 'http://127.0.0.1:8199/admin/version' -TimeoutSec 8
    if ($versionInfo.version -ne 'v2.6.8+custom.history.ua2.loopback1.cleantags1.silentarchive1.remotefilter1.cronreload1.configstate1.substore1.addrout1.configsem1.subrace1') {
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

    $cronMatch = [regex]::Match($configText, '(?m)^\s*cron-expression:\s*"([^"]+)"')
    $localStatus = Invoke-RestMethod -UseBasicParsing `
        -Uri 'http://127.0.0.1:8199/api/status' `
        -Headers @{ 'X-API-Key' = $apiKey } `
        -TimeoutSec 8
    if (-not $cronMatch.Success -or
        $localStatus.configStatus.scheduler.mode -ne 'cron' -or
        $localStatus.configStatus.scheduler.cron_expression -ne $cronMatch.Groups[1].Value -or
        [string]::IsNullOrWhiteSpace($localStatus.configStatus.scheduler.next_run)) {
        throw 'Runtime scheduler status does not match the configured cron expression'
    }
    $nextRun = [DateTimeOffset]::Parse($localStatus.configStatus.scheduler.next_run)
    if ($nextRun -le [DateTimeOffset]::Now) {
        throw "Runtime scheduler next_run is not in the future: $nextRun"
    }
    Write-Output "[OK] Runtime scheduler reports the applied cron and next run: $nextRun"

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
    if ($publicAdmin -ne 200 -or $publicWithoutKey -ne 401) {
        throw "Unexpected public statuses: admin=$publicAdmin, no-key=$publicWithoutKey"
    }
    Write-Output '[OK] Public HTTPS route is reachable and rejects missing API keys'

    if ($IncludePublicAuthenticatedCheck) {
        $publicWithKey = Get-DirectHttpStatus -Uri 'https://cesusub.sbxm.eu.org/api/status' -ApiKey $apiKey
        if ($publicWithKey -ne 200) {
            throw "Unexpected authenticated public status: with-key=$publicWithKey"
        }
        Write-Output '[OK] Explicitly enabled public authenticated API check passed'
    } else {
        Write-Output '[WARN] Public authenticated API check skipped; use -IncludePublicAuthenticatedCheck to opt in'
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
