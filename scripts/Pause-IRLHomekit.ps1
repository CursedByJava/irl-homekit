# Pause IRL Homekit: stops the phone receivers/switcher and keeps the watchdog from relaunching them or OBS.
# OBS itself is left open so you can switch to your normal Twitch profile. Undo with Resume-IRLHomekit.ps1.
New-Item -ItemType File -Force (Join-Path (Split-Path $PSScriptRoot -Parent) 'PAUSE') | Out-Null
Get-Process -Name noalbs, go-irl, mediamtx -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host 'IRL Homekit paused. Run Resume-IRLHomekit.ps1 to turn it back on.'
