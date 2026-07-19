[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$upstreamVersion = 'v2.6.8'
$upstreamCommit = '5fe3a39'
$patch = Join-Path $workspace 'patches\subs-check-pro-v2.6.8-custom-rename.patch'
$destination = Join-Path $workspace 'runtime\bin\subs-check-pro-custom-v2.6.8.exe'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$buildDir = Join-Path $tempRoot ('subs-check-pro-v2.6.8-' + [guid]::NewGuid().ToString('N'))
$buildDir = [IO.Path]::GetFullPath($buildDir)

if (-not $buildDir.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Temporary build path escaped the system temporary directory.'
}
if (-not (Test-Path -LiteralPath $patch -PathType Leaf)) {
    throw "Patch is missing: $patch"
}

try {
    & git clone --branch $upstreamVersion --depth 1 `
        https://github.com/sinspired/subs-check-pro.git $buildDir
    if ($LASTEXITCODE -ne 0) { throw 'git clone failed' }

    & git -C $buildDir apply --check $patch
    if ($LASTEXITCODE -ne 0) { throw 'custom rename patch check failed' }
    & git -C $buildDir apply $patch
    if ($LASTEXITCODE -ne 0) { throw 'custom rename patch failed' }

    Push-Location -LiteralPath $buildDir
    try {
        & go test ./proxy ./check
        if ($LASTEXITCODE -ne 0) { throw 'Go tests failed' }

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
            -ldflags ("-s -w -X main.Version=$upstreamVersion+custom.rename -X main.CurrentCommit=$upstreamCommit-custom") `
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
