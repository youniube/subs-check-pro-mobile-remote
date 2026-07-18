[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $PSScriptRoot 'launch-all.ps1'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$name = 'SubsCheckProMobile'
$powerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

if (-not (Test-Path -LiteralPath $launcher)) {
    throw "Launcher is missing: $launcher"
}

$value = '"' + $powerShellExe + '" -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $launcher + '"'
if (Get-ItemProperty -LiteralPath $runKey -Name $name -ErrorAction SilentlyContinue) {
    Set-ItemProperty -LiteralPath $runKey -Name $name -Value $value
} else {
    New-ItemProperty -LiteralPath $runKey -Name $name -Value $value -PropertyType String | Out-Null
}

& $launcher
Write-Output 'Current-user auto-start installed and services launched.'
