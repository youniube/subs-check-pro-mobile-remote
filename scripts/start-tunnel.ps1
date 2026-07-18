[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $workspace 'runtime'
$exe = Join-Path $runtime 'bin\cloudflared.exe'
$config = Join-Path $runtime 'cloudflared\config.yml'
$logs = Join-Path $runtime 'logs'
$lockPath = Join-Path $runtime 'cloudflared.lock'

foreach ($path in @($exe, $config)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required tunnel file is missing: $path"
    }
}
if (-not (Test-Path -LiteralPath $logs)) {
    New-Item -ItemType Directory -Path $logs | Out-Null
}

try {
    $lock = [IO.File]::Open(
        $lockPath,
        [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None
    )
} catch {
    exit 0
}

try {
    while ($true) {
        $runId = Get-Date -Format 'yyyy-MM-dd-HHmmss'
        $stdoutLog = Join-Path $logs ("cloudflared-{0}.log" -f $runId)
        $stderrLog = Join-Path $logs ("cloudflared-{0}.error.log" -f $runId)
        $processParams = @{
            FilePath               = $exe
            ArgumentList           = @('tunnel', '--config', $config, '--no-autoupdate', 'run')
            WorkingDirectory       = (Split-Path -Parent $exe)
            NoNewWindow            = $true
            PassThru               = $true
            Wait                   = $true
            RedirectStandardOutput = $stdoutLog
            RedirectStandardError  = $stderrLog
        }
        $process = Start-Process @processParams
        Start-Sleep -Seconds 5
    }
} finally {
    $lock.Dispose()
}
