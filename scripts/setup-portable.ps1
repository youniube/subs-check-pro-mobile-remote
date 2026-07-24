[CmdletBinding()]
param(
    [string]$WebHostname,
    [string]$SubStoreHostname,
    [string]$TunnelCredentialsPath,
    [switch]$SkipTunnel,
    [switch]$NoAutoStart,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $workspace 'runtime'
$configTemplate = Join-Path $runtime 'config\config.yaml.example'
$configPath = Join-Path $runtime 'config\config.yaml'
$cloudflaredTemplate = Join-Path $runtime 'cloudflared\config.yml.example'
$cloudflaredConfig = Join-Path $runtime 'cloudflared\config.yml'
$credentialsDestination = Join-Path $runtime 'cloudflared\credentials.json'

foreach ($required in @(
    (Join-Path $runtime 'bin\subs-check-pro.exe'),
    (Join-Path $runtime 'bin\cloudflared.exe'),
    $configTemplate,
    $cloudflaredTemplate
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Portable package is incomplete: $required"
    }
}

function New-RandomToken {
    param([int]$Bytes = 32)

    $buffer = New-Object byte[] $Bytes
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($buffer)
    } finally {
        $generator.Dispose()
    }
    return ([Convert]::ToBase64String($buffer)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Set-YamlScalar {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $pattern = '(?m)^' + [regex]::Escape($Key) + ':\s*.*$'
    if (-not [regex]::IsMatch($Text, $pattern)) {
        throw "Configuration key is missing: $Key"
    }
    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    return [regex]::Replace($Text, $pattern, ($Key + ': "' + $escaped + '"'), 1)
}

function Test-Hostname {
    param([string]$Hostname)

    if ([string]::IsNullOrWhiteSpace($Hostname)) {
        return $false
    }
    return $Hostname -match '^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$' -and
        $Hostname -notmatch '\.\.'
}

if ((Test-Path -LiteralPath $configPath) -and -not $Force) {
    Write-Output 'Existing runtime\config\config.yaml was preserved.'
} else {
    $configText = [IO.File]::ReadAllText($configTemplate, [Text.Encoding]::UTF8)
    $outputPath = (Join-Path $runtime 'output').Replace('\', '/')
    $configText = Set-YamlScalar -Text $configText -Key 'api-key' -Value (New-RandomToken)
    $configText = Set-YamlScalar -Text $configText -Key 'sub-store-path' `
        -Value ('/' + (New-RandomToken -Bytes 24))
    $configText = Set-YamlScalar -Text $configText -Key 'output-dir' -Value $outputPath
    [IO.Directory]::CreateDirectory((Split-Path -Parent $configPath)) | Out-Null
    [IO.File]::WriteAllText($configPath, $configText, [Text.UTF8Encoding]::new($false))
    Write-Output 'Generated local API key and private Sub-Store path in runtime\config\config.yaml.'
}

$tunnelConfigured = $false
if (-not $SkipTunnel) {
    if (-not $TunnelCredentialsPath) {
        Write-Output ''
        Write-Output 'Cloudflare Tunnel is optional during first setup.'
        $TunnelCredentialsPath = Read-Host 'credentials.json path (leave empty for local-only setup)'
    }

    if ($TunnelCredentialsPath) {
        $credentialsSource = [IO.Path]::GetFullPath($TunnelCredentialsPath)
        if (-not (Test-Path -LiteralPath $credentialsSource -PathType Leaf)) {
            throw "Tunnel credentials file was not found: $credentialsSource"
        }
        if ([IO.Path]::GetFullPath($credentialsDestination) -ne $credentialsSource) {
            Copy-Item -LiteralPath $credentialsSource -Destination $credentialsDestination -Force
        }

        if (-not $WebHostname) {
            $WebHostname = Read-Host 'WebUI hostname, for example subs.example.com'
        }
        if (-not (Test-Hostname $WebHostname)) {
            throw "Invalid WebUI hostname: $WebHostname"
        }
        if (-not $SubStoreHostname) {
            $SubStoreHostname = Read-Host 'Sub-Store hostname (leave empty to keep it local-only)'
        }
        if ($SubStoreHostname -and -not (Test-Hostname $SubStoreHostname)) {
            throw "Invalid Sub-Store hostname: $SubStoreHostname"
        }

        $credentials = Get-Content -LiteralPath $credentialsDestination -Raw | ConvertFrom-Json
        $tunnelId = [string]$credentials.TunnelID
        if (-not $tunnelId) {
            throw 'Tunnel credentials do not contain TunnelID.'
        }

        $credentialsYamlPath = ([IO.Path]::GetFullPath($credentialsDestination)).Replace("'", "''")
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add("tunnel: $tunnelId")
        $lines.Add("credentials-file: '$credentialsYamlPath'")
        $lines.Add('protocol: http2')
        $lines.Add('edge-ip-version: "4"')
        $lines.Add('metrics: 127.0.0.1:49312')
        $lines.Add('loglevel: info')
        $lines.Add('')
        $lines.Add('ingress:')
        $lines.Add("  - hostname: $WebHostname")
        $lines.Add('    service: http://127.0.0.1:8199')
        $lines.Add('    originRequest:')
        $lines.Add('      connectTimeout: 10s')
        if ($SubStoreHostname) {
            $lines.Add("  - hostname: $SubStoreHostname")
            $lines.Add('    service: http://127.0.0.1:8299')
            $lines.Add('    originRequest:')
            $lines.Add('      connectTimeout: 10s')
        }
        $lines.Add('  - service: http_status:404')
        [IO.File]::WriteAllLines(
            $cloudflaredConfig,
            $lines,
            [Text.UTF8Encoding]::new($false)
        )
        $tunnelConfigured = $true
        Write-Output 'Cloudflare Tunnel configuration was generated.'
    } else {
        Write-Output 'Tunnel setup was skipped; local WebUI remains available on 127.0.0.1:8199.'
    }
}

if (-not $NoAutoStart) {
    & (Join-Path $PSScriptRoot 'install-current-user.ps1')
} else {
    Write-Output 'Auto-start installation was skipped.'
}

Write-Output ''
Write-Output 'Setup completed.'
if ($tunnelConfigured) {
    Write-Output "WebUI: https://$WebHostname/admin"
} else {
    Write-Output 'WebUI: http://127.0.0.1:8199/admin'
}
Write-Output 'API key location: runtime\config\config.yaml'
Write-Output 'Run verify.cmd to check this computer.'
