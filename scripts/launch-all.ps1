[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$scripts = @((Join-Path $PSScriptRoot 'start.ps1'))
$tunnelExe = Join-Path $workspace 'runtime\bin\cloudflared.exe'
$tunnelConfig = Join-Path $workspace 'runtime\cloudflared\config.yml'
$tunnelCredentials = Join-Path $workspace 'runtime\cloudflared\credentials.json'
if ((Test-Path -LiteralPath $tunnelExe -PathType Leaf) -and
    (Test-Path -LiteralPath $tunnelConfig -PathType Leaf) -and
    (Test-Path -LiteralPath $tunnelCredentials -PathType Leaf)) {
    $scripts += Join-Path $PSScriptRoot 'start-tunnel.ps1'
}

foreach ($script in $scripts) {
    if (-not (Test-Path -LiteralPath $script)) {
        throw "Startup script is missing: $script"
    }
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $script
    ) -WindowStyle Hidden
}
