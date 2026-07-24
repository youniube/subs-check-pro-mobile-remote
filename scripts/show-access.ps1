[CmdletBinding()]
param()

$workspace = Split-Path -Parent $PSScriptRoot
$config = Join-Path $workspace 'runtime\config\config.yaml'
$tunnelConfig = Join-Path $workspace 'runtime\cloudflared\config.yml'
if (-not (Test-Path -LiteralPath $config)) {
    throw "Config not found: $config"
}

$apiLine = Get-Content -LiteralPath $config |
    Where-Object { $_ -match '^api-key:\s*' } |
    Select-Object -First 1
$apiKey = ($apiLine -replace '^api-key:\s*', '').Trim().Trim('"').Trim("'")

$webUrl = 'http://127.0.0.1:8199/admin'
if (Test-Path -LiteralPath $tunnelConfig -PathType Leaf) {
    $tunnelText = [IO.File]::ReadAllText($tunnelConfig)
    $match = [regex]::Match(
        $tunnelText,
        '(?ms)^\s*-\s*hostname:\s*([^\s]+)\s*\r?\n\s*service:\s*http://127\.0\.0\.1:8199\s*$'
    )
    if ($match.Success) {
        $webUrl = 'https://' + $match.Groups[1].Value + '/admin'
    }
}

Write-Output "WebUI: $webUrl"
Write-Output "API Key: $apiKey"
