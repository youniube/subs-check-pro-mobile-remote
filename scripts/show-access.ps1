[CmdletBinding()]
param()

$workspace = Split-Path -Parent $PSScriptRoot
$config = Join-Path $workspace 'runtime\config\config.yaml'
if (-not (Test-Path -LiteralPath $config)) {
    throw "Config not found: $config"
}

$apiLine = Get-Content -LiteralPath $config |
    Where-Object { $_ -match '^api-key:\s*' } |
    Select-Object -First 1
$apiKey = ($apiLine -replace '^api-key:\s*', '').Trim().Trim('"').Trim("'")

Write-Output 'WebUI: https://cesusub.sbxm.eu.org/admin'
Write-Output "API Key: $apiKey"
