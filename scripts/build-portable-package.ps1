[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$CorePath,
    [string]$CloudflaredPath
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$packageName = 'subs-check-pro-portable-windows-amd64'

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $workspace 'dist'
}
if (-not $CorePath) {
    $CorePath = Join-Path $workspace 'runtime\bin\subs-check-pro-custom-v2.6.8.exe'
}
if (-not $CloudflaredPath) {
    $CloudflaredPath = Join-Path $workspace 'runtime\bin\cloudflared.exe'
}

$workspaceFull = [IO.Path]::GetFullPath($workspace)
$outputFull = [IO.Path]::GetFullPath($OutputDirectory)
if (-not $outputFull.StartsWith($workspaceFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Portable package output must remain inside the workspace.'
}

foreach ($required in @($CorePath, $CloudflaredPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required binary is missing: $required"
    }
}

$expectedCloudflaredHash = (
    Get-Content -LiteralPath (Join-Path $workspace 'runtime\cloudflared\SHA256') -Raw
).Trim().ToUpperInvariant()
$actualCloudflaredHash = (Get-FileHash -LiteralPath $CloudflaredPath -Algorithm SHA256).Hash
if ($actualCloudflaredHash -ne $expectedCloudflaredHash) {
    throw "cloudflared checksum mismatch: expected $expectedCloudflaredHash, got $actualCloudflaredHash"
}

$stagingRoot = Join-Path $outputFull $packageName
$zipPath = Join-Path $outputFull ($packageName + '.zip')
$zipHashPath = $zipPath + '.sha256'

if (-not (Test-Path -LiteralPath $outputFull)) {
    New-Item -ItemType Directory -Path $outputFull | Out-Null
}
foreach ($target in @($stagingRoot, $zipPath, $zipHashPath)) {
    if (-not (Test-Path -LiteralPath $target)) {
        continue
    }
    $resolvedTarget = [IO.Path]::GetFullPath($target)
    if (-not $resolvedTarget.StartsWith($outputFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Portable package cleanup target escaped the output directory.'
    }
    Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
}

$directories = @(
    $stagingRoot,
    (Join-Path $stagingRoot 'scripts'),
    (Join-Path $stagingRoot 'runtime\bin'),
    (Join-Path $stagingRoot 'runtime\config'),
    (Join-Path $stagingRoot 'runtime\cloudflared')
)
foreach ($directory in $directories) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

Copy-Item -LiteralPath $CorePath `
    -Destination (Join-Path $stagingRoot 'runtime\bin\subs-check-pro.exe')
Copy-Item -LiteralPath $CloudflaredPath `
    -Destination (Join-Path $stagingRoot 'runtime\bin\cloudflared.exe')

$rootFiles = @(
    'README-PORTABLE.md',
    'setup.cmd',
    'start.cmd',
    'verify.cmd'
)
foreach ($file in $rootFiles) {
    Copy-Item -LiteralPath (Join-Path $workspace $file) -Destination $stagingRoot
}

$scriptFiles = @(
    'setup-portable.ps1',
    'verify-portable.ps1',
    'start.ps1',
    'start-tunnel.ps1',
    'launch-all.ps1',
    'install.ps1',
    'install-current-user.ps1',
    'show-access.ps1'
)
foreach ($file in $scriptFiles) {
    Copy-Item -LiteralPath (Join-Path $workspace ('scripts\' + $file)) `
        -Destination (Join-Path $stagingRoot 'scripts')
}

Copy-Item -LiteralPath (Join-Path $workspace 'runtime\config\config.yaml.example') `
    -Destination (Join-Path $stagingRoot 'runtime\config\config.yaml.example')
Copy-Item -LiteralPath (Join-Path $workspace 'runtime\cloudflared\config.yml.example') `
    -Destination (Join-Path $stagingRoot 'runtime\cloudflared\config.yml.example')
Copy-Item -LiteralPath (Join-Path $workspace 'runtime\cloudflared\VERSION') `
    -Destination (Join-Path $stagingRoot 'runtime\cloudflared\VERSION')
Copy-Item -LiteralPath (Join-Path $workspace 'runtime\cloudflared\SHA256') `
    -Destination (Join-Path $stagingRoot 'runtime\cloudflared\SHA256')
Copy-Item -LiteralPath (Join-Path $workspace 'runtime\VERSION') `
    -Destination (Join-Path $stagingRoot 'runtime\VERSION')

$forbiddenFiles = @(
    'runtime\config\config.yaml',
    'runtime\cloudflared\config.yml',
    'runtime\cloudflared\credentials.json',
    'runtime\cloudflared\cert.pem'
)
foreach ($relativePath in $forbiddenFiles) {
    if (Test-Path -LiteralPath (Join-Path $stagingRoot $relativePath)) {
        throw "Portable package contains a forbidden private file: $relativePath"
    }
}

$manifest = [ordered]@{
    package = $packageName
    platform = 'windows-amd64'
    core_version = (Get-Content -LiteralPath (Join-Path $workspace 'runtime\VERSION') -Raw).Trim()
    cloudflared_version = (
        Get-Content -LiteralPath (Join-Path $workspace 'runtime\cloudflared\VERSION') -Raw
    ).Trim()
    files = [ordered]@{
        'runtime/bin/subs-check-pro.exe' = (
            Get-FileHash -LiteralPath (Join-Path $stagingRoot 'runtime\bin\subs-check-pro.exe') `
                -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        'runtime/bin/cloudflared.exe' = (
            Get-FileHash -LiteralPath (Join-Path $stagingRoot 'runtime\bin\cloudflared.exe') `
                -Algorithm SHA256
        ).Hash.ToLowerInvariant()
    }
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content `
    -LiteralPath (Join-Path $stagingRoot 'manifest.json') -Encoding UTF8

Compress-Archive -LiteralPath $stagingRoot -DestinationPath $zipPath -CompressionLevel Optimal
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(
    $zipHashPath,
    ($zipHash + '  ' + [IO.Path]::GetFileName($zipPath) + [Environment]::NewLine),
    [Text.UTF8Encoding]::new($false)
)

Write-Output "Portable package: $zipPath"
Write-Output "SHA256 file: $zipHashPath"
