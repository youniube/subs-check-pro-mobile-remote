[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $workspace 'runtime'
$exe = Join-Path $runtime 'bin\subs-check-pro.exe'
$config = Join-Path $runtime 'config\config.yaml'
$logs = Join-Path $runtime 'logs'
$lockPath = Join-Path $runtime 'subs-check-pro.lock'

# Keep successful checks and save messages visible. The upstream also writes the
# configured API key at info level, so Protect-MainLog masks that exact value in
# the redirected log without changing the file length while the process is live.
$env:LOG_LEVEL = 'info'
$script:mainLogOffsets = @{}

# v2.6.x rejects a host-qualified sub-store-port even though its runtime
# supports one. Pass only the numeric port in YAML and force the embedded
# Sub-Store backend to remain on loopback through its supported environment.
$env:SUB_STORE_BACKEND_API_HOST = '127.0.0.1'

if (-not (Test-Path -LiteralPath $exe)) {
    throw "Executable not found: $exe"
}
if (-not (Test-Path -LiteralPath $config)) {
    throw "Config not found: $config"
}
if (-not (Test-Path -LiteralPath $logs)) {
    New-Item -ItemType Directory -Path $logs | Out-Null
}

function Protect-SubStoreLog {
    # The embedded Sub-Store prints its private backend path at startup.
    # Scrub only that exact value while preserving the rest of its log.
    $subStoreLog = Join-Path $runtime 'output\sub-store\sub-store.log'
    if (-not (Test-Path -LiteralPath $subStoreLog)) {
        return
    }

    try {
        $configText = [IO.File]::ReadAllText($config)
        $pathMatch = [regex]::Match(
            $configText,
            '(?m)^[ \t]*sub-store-path:[ \t]*"([^"]+)"'
        )
        if (-not $pathMatch.Success -or $pathMatch.Groups[1].Value -eq '') {
            return
        }
        $privatePath = $pathMatch.Groups[1].Value

        $readStream = [IO.File]::Open(
            $subStoreLog,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::ReadWrite
        )
        try {
            $reader = New-Object IO.StreamReader(
                $readStream,
                [Text.UTF8Encoding]::new($false),
                $true
            )
            try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally {
            $readStream.Dispose()
        }

        if (-not $content.Contains($privatePath)) {
            return
        }

        $bytes = [Text.UTF8Encoding]::new($false).GetBytes(
            $content.Replace($privatePath, '<redacted>')
        )
        $writeStream = [IO.File]::Open(
            $subStoreLog,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Write,
            [IO.FileShare]::ReadWrite
        )
        try {
            $writeStream.SetLength(0)
            $writeStream.Write($bytes, 0, $bytes.Length)
            $writeStream.Flush()
        } finally {
            $writeStream.Dispose()
        }
    } catch {
        # Log scrubbing must never stop the service watchdog.
    }
}

function Protect-MainLog {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    try {
        $configText = [IO.File]::ReadAllText($config)
        $keyMatch = [regex]::Match(
            $configText,
            '(?m)^[ \t]*api-key:[ \t]*"([^"]+)"'
        )
        if (-not $keyMatch.Success) {
            return
        }

        $encoding = [Text.UTF8Encoding]::new($false)
        $secret = $encoding.GetBytes($keyMatch.Groups[1].Value)
        if ($secret.Length -eq 0) {
            return
        }

        $stream = [IO.File]::Open(
            $Path,
            [IO.FileMode]::Open,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::ReadWrite
        )
        try {
            if ($stream.Length -lt $secret.Length) {
                return
            }

            $start = 0L
            if ($script:mainLogOffsets.ContainsKey($Path)) {
                $previousLength = [long]$script:mainLogOffsets[$Path]
                if ($previousLength -le $stream.Length) {
                    $start = [Math]::Max(0L, $previousLength - $secret.Length + 1)
                }
            }
            $remaining = $stream.Length - $start
            if ($remaining -gt [int]::MaxValue) {
                return
            }

            $stream.Seek($start, [IO.SeekOrigin]::Begin) | Out-Null
            $content = New-Object byte[] ([int]$remaining)
            $read = 0
            while ($read -lt $content.Length) {
                $count = $stream.Read($content, $read, $content.Length - $read)
                if ($count -eq 0) {
                    break
                }
                $read += $count
            }

            $changed = $false
            for ($index = 0; $index -le $read - $secret.Length; $index++) {
                $matches = $true
                for ($offset = 0; $offset -lt $secret.Length; $offset++) {
                    if ($content[$index + $offset] -ne $secret[$offset]) {
                        $matches = $false
                        break
                    }
                }
                if (-not $matches) {
                    continue
                }

                for ($offset = 0; $offset -lt $secret.Length; $offset++) {
                    $content[$index + $offset] = 0x2A
                }
                $index += $secret.Length - 1
                $changed = $true
            }

            if ($changed) {
                $stream.Seek($start, [IO.SeekOrigin]::Begin) | Out-Null
                $stream.Write($content, 0, $read)
                $stream.Flush()
            }
            $script:mainLogOffsets[$Path] = $stream.Length
        } finally {
            $stream.Dispose()
        }
    } catch {
        # Credential scrubbing must never stop the service watchdog.
    }
}

try {
    $lock = [IO.File]::Open(
        $lockPath,
        [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None
    )
} catch {
    # Another instance owns the lock. Do not start a duplicate process.
    exit 0
}

$oldLocation = Get-Location

try {
    Set-Location -LiteralPath (Split-Path -Parent $exe)
    while ($true) {
        $runId = Get-Date -Format 'yyyy-MM-dd-HHmmss'
        $stdoutLog = Join-Path $logs ("subs-check-pro-{0}.log" -f $runId)
        $stderrLog = Join-Path $logs ("subs-check-pro-{0}.error.log" -f $runId)
        $processParams = @{
            FilePath               = $exe
            ArgumentList           = @('-f', $config)
            WorkingDirectory       = (Split-Path -Parent $exe)
            NoNewWindow            = $true
            PassThru               = $true
            RedirectStandardOutput = $stdoutLog
            RedirectStandardError  = $stderrLog
        }
        $process = Start-Process @processParams
        while (-not $process.HasExited) {
            Start-Sleep -Milliseconds 500
            Protect-MainLog -Path $stdoutLog
            Protect-SubStoreLog
            $process.Refresh()
        }
        Protect-MainLog -Path $stdoutLog
        Protect-SubStoreLog
        Start-Sleep -Seconds 5
    }
} finally {
    Set-Location -LiteralPath $oldLocation
    $lock.Dispose()
}
