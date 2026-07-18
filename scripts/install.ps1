[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot 'install-current-user.ps1'

if (-not (Test-Path -LiteralPath $installer)) {
    throw "Installer not found: $installer"
}

# Compatibility entry point: this deployment intentionally avoids UAC,
# Windows services, firewall changes, and the retired Tailscale plan.
& $installer
exit $LASTEXITCODE
