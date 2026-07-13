$ErrorActionPreference = 'Continue'

$Root = $PSScriptRoot
$VenvRoot = 'C:\Users\Admin\kokoro-tts\.venv'
$VenvSitePackages = Join-Path $VenvRoot 'Lib\site-packages'
$BasePythonRoot = 'C:\Users\Admin\AppData\Roaming\uv\python\cpython-3.11-windows-x86_64-none'
$PythonCandidates = @(
    (Join-Path $Root '.venv\Scripts\pythonw.exe'),
    (Join-Path $BasePythonRoot 'pythonw.exe'),
    (Join-Path $Root '.venv\Scripts\python.exe'),
    (Join-Path $BasePythonRoot 'python.exe'),
    (Join-Path $VenvRoot 'Scripts\python.exe')
)
$Python = $PythonCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
$Server = Join-Path $Root 'kokoro_server.py'
$LogDir = Join-Path $Root 'logs'
$WatchdogLog = Join-Path $LogDir 'kokoro_watchdog.log'
$ServerLog = Join-Path $LogDir 'kokoro_server.log'
$ServerErrLog = Join-Path $LogDir 'kokoro_server.err.log'
$HealthUrl = 'http://127.0.0.1:8765/health'
$CheckSeconds = 30
$StartupTimeoutSeconds = 120

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-WatchdogLog {
    param([string]$Message)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $WatchdogLog -Value "[$stamp] $Message"
}

function Test-KokoroHealth {
    try {
        $response = Invoke-RestMethod -Uri $HealthUrl -TimeoutSec 3
        return ($response.ok -eq $true)
    } catch {
        return $false
    }
}

function Get-KokoroServerProcesses {
    Get-CimInstance Win32_Process |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -match 'kokoro_server\.py' -and
            $_.CommandLine -notmatch 'kokoro_watchdog\.ps1'
        }
}

function Stop-StaleKokoroServers {
    $stale = Get-KokoroServerProcesses
    foreach ($proc in $stale) {
        try {
            Write-WatchdogLog "Stopping stale Kokoro server PID $($proc.ProcessId)."
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        } catch {
            Write-WatchdogLog "Failed to stop stale Kokoro PID $($proc.ProcessId): $($_.Exception.Message)"
        }
    }
}

function Get-KokoroListeningPid {
    try {
        $conn = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($conn) { return [int]$conn.OwningProcess }
    } catch {}
    return $null
}

function Stop-DuplicateKokoroServers {
    $listeningPid = Get-KokoroListeningPid
    if (-not $listeningPid) { return }

    $servers = Get-KokoroServerProcesses
    foreach ($proc in $servers) {
        if ([int]$proc.ProcessId -ne [int]$listeningPid) {
            try {
                Write-WatchdogLog "Stopping duplicate non-listening Kokoro server PID $($proc.ProcessId); keeping listener PID $listeningPid."
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
            } catch {
                Write-WatchdogLog "Failed to stop duplicate Kokoro PID $($proc.ProcessId): $($_.Exception.Message)"
            }
        }
    }
}

function Start-KokoroServer {
    if (Test-KokoroHealth) {
        return $true
    }

    Stop-StaleKokoroServers

    $pythonCommand = $null
    $pythonArguments = $null
    if ($Python -and (Test-Path $Python)) {
        $pythonCommand = $Python
        $pythonArguments = "-u `"$Server`""
    } else {
        $pythonInfo = Get-Command python -ErrorAction SilentlyContinue
        if ($pythonInfo) {
            $pythonCommand = $pythonInfo.Source
            $pythonArguments = "-u `"$Server`""
        } else {
            $pyInfo = Get-Command py -ErrorAction SilentlyContinue
            if ($pyInfo) {
                $pythonCommand = $pyInfo.Source
                $pythonArguments = "-3 -u `"$Server`""
            }
        }
    }

    if (-not $pythonCommand) {
        Write-WatchdogLog "ERROR: Python not found in known Kokoro venvs and no Python launcher was available on PATH."
        return $false
    }
    if (-not (Test-Path $Server)) {
        Write-WatchdogLog "ERROR: Server script not found at $Server"
        return $false
    }

    Write-WatchdogLog 'Starting Kokoro server.'
    try {
        # Use CreateNoWindow with redirected output. Do not route through cmd.exe:
        # cmd can create the blank console window this daemon is meant to avoid.
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $pythonCommand
        $startInfo.Arguments = $pythonArguments
        $startInfo.WorkingDirectory = $Root
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        if (Test-Path $VenvSitePackages) {
            $startInfo.EnvironmentVariables['PYTHONPATH'] = $VenvSitePackages
            $startInfo.EnvironmentVariables['VIRTUAL_ENV'] = $VenvRoot
            $startInfo.EnvironmentVariables['PATH'] = (Join-Path $VenvRoot 'Scripts') + ';' + $startInfo.EnvironmentVariables['PATH']
        }
        $proc = [System.Diagnostics.Process]::new()
        $proc.StartInfo = $startInfo
        Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action {
            if ($EventArgs.Data) { Add-Content -LiteralPath $Event.MessageData -Value $EventArgs.Data }
        } -MessageData $ServerLog | Out-Null
        Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action {
            if ($EventArgs.Data) { Add-Content -LiteralPath $Event.MessageData -Value $EventArgs.Data }
        } -MessageData $ServerErrLog | Out-Null
        [void]$proc.Start()
        $proc.BeginOutputReadLine()
        $proc.BeginErrorReadLine()
        Write-WatchdogLog "Started hidden Kokoro server PID $($proc.Id) using $pythonCommand."
    } catch {
        Write-WatchdogLog "ERROR: Failed to launch Kokoro server: $($_.Exception.Message)"
        return $false
    }

    $deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        if (Test-KokoroHealth) {
            Write-WatchdogLog 'Kokoro server is healthy.'
            return $true
        }
    }

    Write-WatchdogLog "ERROR: Kokoro server did not become healthy within $StartupTimeoutSeconds seconds."
    return $false
}

Write-WatchdogLog 'Watchdog started.'
while ($true) {
    if (-not (Test-KokoroHealth)) {
        Write-WatchdogLog 'Health check failed.'
        Start-KokoroServer | Out-Null
    }
    Start-Sleep -Seconds $CheckSeconds
}
