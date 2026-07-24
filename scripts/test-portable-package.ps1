[CmdletBinding()]
param(
    [string]$ZipPath
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
if (-not $ZipPath) {
    $ZipPath = Join-Path $workspace 'dist\subs-check-pro-portable-windows-amd64.zip'
}
$ZipPath = [IO.Path]::GetFullPath($ZipPath)
if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
    throw "Portable package was not found: $ZipPath"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
try {
    $entries = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    $required = @(
        '/setup.cmd',
        '/README-PORTABLE.md',
        '/manifest.json',
        '/runtime/bin/subs-check-pro.exe',
        '/runtime/bin/cloudflared.exe',
        '/scripts/setup-portable.ps1',
        '/scripts/verify-portable.ps1'
    )
    foreach ($suffix in $required) {
        if (-not ($entries | Where-Object { $_.EndsWith($suffix) })) {
            throw "Portable archive entry is missing: $suffix"
        }
    }

    $forbidden = @(
        '/runtime/config/config.yaml',
        '/runtime/cloudflared/config.yml',
        '/runtime/cloudflared/credentials.json',
        '/runtime/cloudflared/cert.pem'
    )
    foreach ($suffix in $forbidden) {
        if ($entries | Where-Object { $_.EndsWith($suffix) }) {
            throw "Portable archive contains a private runtime file: $suffix"
        }
    }
} finally {
    $archive.Dispose()
}

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempRoot ('subs-check-portable-test-' + [guid]::NewGuid().ToString('N'))
$testRoot = [IO.Path]::GetFullPath($testRoot)
if (-not $testRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Portable smoke-test path escaped the system temporary directory.'
}

try {
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $testRoot
    $packageRoot = Get-ChildItem -LiteralPath $testRoot -Directory | Select-Object -First 1
    if (-not $packageRoot) {
        throw 'Portable archive did not contain a package directory.'
    }

    $setup = Join-Path $packageRoot.FullName 'scripts\setup-portable.ps1'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
        -File $setup -SkipTunnel -NoAutoStart
    if ($LASTEXITCODE -ne 0) {
        throw "Portable setup smoke test failed with exit code $LASTEXITCODE"
    }

    $config = Join-Path $packageRoot.FullName 'runtime\config\config.yaml'
    $configText = [IO.File]::ReadAllText($config)
    if ([regex]::IsMatch($configText, '(?m)^(?!\s*#).*CHANGE_ME')) {
        throw 'Portable setup left an active placeholder in config.yaml.'
    }
    if ($configText -notmatch '(?m)^api-key:\s*"[^"]{40,}"\s*$') {
        throw 'Portable setup did not generate a strong API key.'
    }
    if ($configText -notmatch '(?m)^sub-store-path:\s*"/[^"]{30,}"\s*$') {
        throw 'Portable setup did not generate a private Sub-Store path.'
    }

    $expectedOutput = (Join-Path $packageRoot.FullName 'runtime\output').Replace('\', '/')
    if (-not $configText.Contains('output-dir: "' + $expectedOutput + '"')) {
        throw 'Portable setup did not use its extracted runtime output directory.'
    }
    if (Test-Path -LiteralPath (
        Join-Path $packageRoot.FullName 'runtime\cloudflared\config.yml'
    )) {
        throw 'Local-only portable setup unexpectedly generated a Tunnel configuration.'
    }

    $manifestPath = Join-Path $packageRoot.FullName 'manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    foreach ($relativePath in @(
        'runtime/bin/subs-check-pro.exe',
        'runtime/bin/cloudflared.exe'
    )) {
        $expectedHash = $manifest.files.$relativePath
        $actualHash = (
            Get-FileHash -LiteralPath (Join-Path $packageRoot.FullName $relativePath) `
                -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "Portable manifest hash mismatch: $relativePath"
        }
    }
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [IO.Path]::GetFullPath($testRoot)
        if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}

Write-Output 'Portable package smoke test passed.'
