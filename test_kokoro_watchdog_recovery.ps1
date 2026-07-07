$ErrorActionPreference = 'Continue'

$Root = $PSScriptRoot
$LogDir = Join-Path $Root 'logs'
$WatchdogLog = Join-Path $LogDir 'kokoro_watchdog.log'

Write-Host '--- target processes before kill ---'
$procs = Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -and
    $_.CommandLine -match 'kokoro_server\.py' -and
    $_.CommandLine -notmatch 'hermes'
}
$procs | Select-Object ProcessId,CommandLine | Format-List
foreach ($p in $procs) {
    Stop-Process -Id $p.ProcessId -Force
    Write-Host "Killed Kokoro server PID $($p.ProcessId)"
}

Start-Sleep -Seconds 50

Write-Host '--- health after watchdog recovery window ---'
try {
    Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -TimeoutSec 10 | ConvertTo-Json -Compress
} catch {
    Write-Host $_.Exception.Message
}

Write-Host '--- kokoro/watchdog processes after recovery ---'
Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -and ($_.CommandLine -match 'kokoro_server\.py|kokoro_watchdog\.ps1')
} | Select-Object ProcessId,CommandLine | Format-List

Write-Host '--- watchdog log tail ---'
Get-Content $WatchdogLog -Tail 80

Write-Host '--- task status ---'
Get-ScheduledTask -TaskName 'Kokoro Read Aloud Server' | Format-List TaskName,State
Get-ScheduledTaskInfo -TaskName 'Kokoro Read Aloud Server' | Format-List LastRunTime,LastTaskResult
