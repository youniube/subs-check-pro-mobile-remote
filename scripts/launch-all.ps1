[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scripts = @(
    (Join-Path $PSScriptRoot 'start.ps1'),
    (Join-Path $PSScriptRoot 'start-tunnel.ps1')
)

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
