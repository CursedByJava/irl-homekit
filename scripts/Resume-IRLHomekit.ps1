# Resume IRL Homekit: removes the pause flag and makes sure the watchdog is running.
# If OBS is already open on another profile, switch it to Profile "IRL Homekit" + Scene Collection "IRL Homekit".
Remove-Item (Join-Path (Split-Path $PSScriptRoot -Parent) 'PAUSE') -Force -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName 'IRL Homekit' -ErrorAction SilentlyContinue
if (-not $?) {
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $PSScriptRoot 'Start-IRLHomekit.ps1'))
}
Write-Host 'IRL Homekit resumed.'
