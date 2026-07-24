[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$upstreamVersion = 'v2.6.8'
$upstreamSourceCommit = '3c5468962e4364c3d5a61b53d90baf10385ea198'
$upstreamCommit = '5fe3a39'
$corePatches = @(
    (Join-Path $workspace 'patches\subs-check-pro-v2.6.8-custom-rename.patch'),
    (Join-Path $workspace 'patches\subs-check-pro-v2.6.8-analysis-report.patch'),
    (Join-Path $workspace 'patches\subs-check-pro-v2.6.8-subscription-history.patch'),
    (Join-Path $workspace 'patches\subs-check-pro-v2.6.8-ua-fallback.patch'),
    (Join-Path $workspace 'patches\subs-check-pro-v2.6.8-loopback-history.patch'),
    (Join-Path $workspace 'patches\subs-check-pro-v2.6.8-clean-internal-tags.patch')
)
$webuiPatches = @(
    (Join-Path $workspace 'patches\subs-check-pro-webui-b8db5f51c367-analysis-report.patch'),
    (Join-Path $workspace 'patches\subs-check-pro-webui-b8db5f51c367-subscription-history.patch')
)
$destination = Join-Path $workspace 'runtime\bin\subs-check-pro-custom-v2.6.8.exe'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$buildDir = Join-Path $tempRoot ('subs-check-pro-v2.6.8-' + [guid]::NewGuid().ToString('N'))
$buildDir = [IO.Path]::GetFullPath($buildDir)

if (-not $buildDir.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Temporary build path escaped the system temporary directory.'
}
foreach ($patch in $corePatches + $webuiPatches) {
    if (-not (Test-Path -LiteralPath $patch -PathType Leaf)) {
        throw "Patch is missing: $patch"
    }
}

try {
    # Git's schannel backend may request an interactive client credential.
    # OpenSSL avoids that Windows UI dependency during unattended builds.
    # Windows PowerShell 5.1 wraps normal Git progress on stderr as error records,
    # so allow that stream here and still decide success from Git's exit code.
    $ErrorActionPreference = 'Continue'
    # The upstream repository stores about 300 MB of embedded Node binaries.
    # Fetch only the Windows amd64 asset required by this build.
    & git init --quiet $buildDir
    $initExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($null -eq $initExitCode -or $initExitCode -ne 0) {
        throw "git init failed with exit code $initExitCode"
    }

    & git -C $buildDir remote add origin 'https://github.com/sinspired/subs-check-pro.git'
    if ($LASTEXITCODE -ne 0) { throw 'Git upstream remote configuration failed' }
    & git -C $buildDir config http.sslBackend openssl
    if ($LASTEXITCODE -ne 0) { throw 'Git OpenSSL backend configuration failed' }

    # v2.6.8 is an annotated tag. A filtered shallow clone can fetch only the tag
    # object on a clean runner, so fetch the immutable peeled commit explicitly.
    $ErrorActionPreference = 'Continue'
    & git -C $buildDir fetch --quiet --filter=blob:none --depth 1 origin $upstreamSourceCommit
    $fetchExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($null -eq $fetchExitCode -or $fetchExitCode -ne 0) {
        throw "Git upstream source fetch failed with exit code $fetchExitCode"
    }

    & git -C $buildDir sparse-checkout init --no-cone
    if ($LASTEXITCODE -ne 0) { throw 'sparse checkout initialization failed' }
    & git -C $buildDir sparse-checkout set '/*' '!/assets/node_*' '/assets/node_windows_amd64.zst' '!/doc/' '!/docs-site/'
    if ($LASTEXITCODE -ne 0) { throw 'sparse checkout configuration failed' }
    & git -C $buildDir checkout --detach --quiet FETCH_HEAD
    if ($LASTEXITCODE -ne 0) { throw 'sparse checkout failed' }
    $checkedOutCommit = ((& git -C $buildDir rev-parse HEAD) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $checkedOutCommit -ne $upstreamSourceCommit) {
        throw "Unexpected upstream source commit: $checkedOutCommit"
    }

    foreach ($patch in $corePatches) {
        & git -C $buildDir apply --check $patch
        if ($LASTEXITCODE -ne 0) { throw "core patch check failed: $patch" }
        & git -C $buildDir apply $patch
        if ($LASTEXITCODE -ne 0) { throw "core patch failed: $patch" }
    }

    Push-Location -LiteralPath $buildDir
    try {
        # `go list -m` can return an empty .Dir when the module cache is clean.
        # Download the selected go.mod version explicitly and use its JSON Dir.
        $webuiDownloadOutput = (& go mod download -json github.com/sinspired/subs-check-pro-webui 2>&1 | Out-String).Trim()
        $webuiDownloadExitCode = $LASTEXITCODE
        if ($webuiDownloadExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($webuiDownloadOutput)) {
            throw "WebUI module download failed: $webuiDownloadOutput"
        }
        try {
            $webuiModuleInfo = $webuiDownloadOutput | ConvertFrom-Json
        } catch {
            throw "WebUI module download returned invalid JSON: $webuiDownloadOutput"
        }
        $webuiModule = [string]$webuiModuleInfo.Dir
        if ($webuiModuleInfo.Error -or [string]::IsNullOrWhiteSpace($webuiModule) -or -not (Test-Path -LiteralPath $webuiModule -PathType Container)) {
            throw 'WebUI module lookup failed'
        }
        $webuiDir = Join-Path $buildDir '_webui'
        Copy-Item -LiteralPath $webuiModule -Destination $webuiDir -Recurse -Force
        Get-ChildItem -LiteralPath $webuiDir -Recurse -File | ForEach-Object { $_.IsReadOnly = $false }

        foreach ($patch in $webuiPatches) {
            & git -C $buildDir apply --check --directory='_webui' $patch
            if ($LASTEXITCODE -ne 0) { throw "WebUI patch check failed: $patch" }
            & git -C $buildDir apply --directory='_webui' $patch
            if ($LASTEXITCODE -ne 0) { throw "WebUI patch failed: $patch" }
        }

        & go mod edit '-replace=github.com/sinspired/subs-check-pro-webui=./_webui'
        if ($LASTEXITCODE -ne 0) { throw 'WebUI module replacement failed' }

        # Upstream ISP tests call ipapi.is directly and fail when that third-party
        # service is slow or unavailable. Keep the deterministic proxy tests,
        # including local-history tag behavior, in the build gate.
        & go test ./proxy -skip 'Test(CurrentIP|SpecificIP|GetISPInfo)$'
        if ($LASTEXITCODE -ne 0) { throw 'Proxy tests failed' }
        & go test ./check
        if ($LASTEXITCODE -ne 0) { throw 'Check tests failed' }

        $goBin = Join-Path (& go env GOPATH) 'bin'
        $winres = Join-Path $goBin 'go-winres.exe'
        if (-not (Test-Path -LiteralPath $winres -PathType Leaf)) {
            & go install github.com/tc-hib/go-winres@v0.3.3
            if ($LASTEXITCODE -ne 0) { throw 'go-winres installation failed' }
        }
        $env:PATH = $goBin + ';' + $env:PATH
        $env:CGO_ENABLED = '0'
        $env:GOOS = 'windows'
        $env:GOARCH = 'amd64'

        & go generate ./...
        if ($LASTEXITCODE -ne 0) { throw 'go generate failed' }

        $built = Join-Path $buildDir 'subs-check-pro-custom.exe'
        & go build -trimpath `
            -ldflags ("-s -w -X main.Version=$upstreamVersion+custom.history.ua2.loopback1.cleantags1 -X main.CurrentCommit=$upstreamCommit-custom") `
            -o $built .
        if ($LASTEXITCODE -ne 0) { throw 'go build failed' }

        Copy-Item -LiteralPath $built -Destination $destination -Force
        Get-FileHash -LiteralPath $destination -Algorithm SHA256
    } finally {
        Pop-Location
    }
} finally {
    if (Test-Path -LiteralPath $buildDir) {
        $resolved = [IO.Path]::GetFullPath($buildDir)
        if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
