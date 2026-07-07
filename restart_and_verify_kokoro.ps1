$ErrorActionPreference = 'Continue'

$Root = $PSScriptRoot
$LogDir = Join-Path $Root 'logs'
$WatchdogLog = Join-Path $LogDir 'kokoro_watchdog.log'
$ServerErrLog = Join-Path $LogDir 'kokoro_server.err.log'

Write-Host 'Stopping scheduled task and any stale Kokoro/watchdog processes...'
Stop-ScheduledTask -TaskName 'Kokoro Read Aloud Server' -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -and ($_.CommandLine -match 'kokoro_server\.py|kokoro_watchdog\.ps1')
} | ForEach-Object {
    Write-Host "Killing PID $($_.ProcessId): $($_.CommandLine)"
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2
Write-Host 'Starting scheduled task...'
Start-ScheduledTask -TaskName 'Kokoro Read Aloud Server'

$deadline = (Get-Date).AddSeconds(180)
$healthy = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    try {
        $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -TimeoutSec 5
        if ($health.ok -eq $true) {
            $healthy = $true
            break
        }
    } catch {}
}

Write-Host '--- health ---'
if ($healthy) {
    Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -TimeoutSec 10 | ConvertTo-Json -Compress
} else {
    Write-Host 'NOT HEALTHY after 180 seconds'
}

Write-Host '--- processes ---'
Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -and ($_.CommandLine -match 'kokoro_server\.py|kokoro_watchdog\.ps1')
} | Select-Object ProcessId,CommandLine | Format-List

Write-Host '--- task ---'
Get-ScheduledTask -TaskName 'Kokoro Read Aloud Server' | Format-List TaskName,State
Get-ScheduledTaskInfo -TaskName 'Kokoro Read Aloud Server' | Format-List LastRunTime,LastTaskResult

Write-Host '--- watchdog log tail ---'
Get-Content $WatchdogLog -Tail 80

Write-Host '--- server err tail ---'
if (Test-Path $ServerErrLog) {
    Get-Content $ServerErrLog -Tail 80
}
