param(
    [switch]$Force
)

$ErrorActionPreference = 'Continue'
Write-Host 'Kokoro process inspection'
$conn = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
$owner = if ($conn) { [int]$conn.OwningProcess } else { $null }
Write-Host "Port 8765 owner: $owner"
$servers = @(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.CommandLine -match 'kokoro_server\.py' })
$servers | Select-Object ProcessId,ParentProcessId,CommandLine | Format-List

if (-not $Force) {
    Write-Host 'Dry run only. Pass -Force to stop server processes that are not the port owner.'
    exit 0
}

foreach ($p in $servers) {
    if ($owner -and [int]$p.ProcessId -ne $owner) {
        Write-Host "Stopping non-listening Kokoro PID $($p.ProcessId)"
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
}
Write-Host '--- after cleanup ---'
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.CommandLine -match 'kokoro_server\.py|kokoro_watchdog\.ps1' } | Select-Object ProcessId,ParentProcessId,CommandLine | Format-List
