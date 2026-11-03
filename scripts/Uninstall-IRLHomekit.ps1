# Uninstalls IRL Homekit: closes it, removes its shortcuts, start-at-sign-in, firewall rules and the Settings > Apps
# entry, and optionally deletes the install folder (settings, passwords, the IRL Homekit OBS and downloaded tools).
# Your normal OBS is not touched. Run from Settings > Apps > IRL Homekit > Uninstall, or the Start menu.
param([string] $InstallDir = (Split-Path $PSScriptRoot -Parent), [switch] $DeleteFiles,
    # No questions (for scripts): uninstall, and delete the install folder only with -DeleteFiles.
    [switch] $Yes)
$ErrorActionPreference = 'Stop'

# Firewall rules need administrator rights: ask once, then continue elevated.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -InstallDir `"$InstallDir`"$(if ($Yes) { ' -Yes' })$(if ($DeleteFiles) { ' -DeleteFiles' })"
    exit
}

Write-Host "`nUninstall IRL Homekit" -ForegroundColor Cyan
Write-Host "This removes IRL Homekit from this PC. Your normal OBS and its scenes are not touched."
if (-not $Yes -and (Read-Host 'Continue? (y/N)') -notmatch '^y') { Write-Host 'Nothing was changed.'; return }
$wipe = $DeleteFiles -or (-not $Yes -and (Read-Host "Also delete $InstallDir (settings, passwords, stream keys, the IRL Homekit OBS)? (y/N)") -match '^y')

# 1. Close it: the app first (so it doesn't restart anything), then OBS and the services.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*Start-IRLHomekit.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-Process obs64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$InstallDir\obs\*" } | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process noalbs, go-irl, mediamtx, caddy -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$InstallDir\*" } | Stop-Process -Force -ErrorAction SilentlyContinue
$dash = (Get-NetTCPConnection -LocalPort 8090 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
if ($dash) { Stop-Process -Id $dash -Force -ErrorAction SilentlyContinue }
Write-Host '  closed'

# 2. Shortcuts and start at sign-in (for the signed-in user, also when this window runs as another admin).
foreach ($p in @(
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'IRL Homekit'),
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'IRL Homekit.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Startup')) 'IRL Homekit.lnk'))) {
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
}
Get-ScheduledTask -TaskName 'IRL Homekit', 'IRL Homekit (sign-in)' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
Write-Host '  shortcuts removed'

# 3. Firewall rules and the Settings > Apps entry.
Get-NetFirewallRule -DisplayName 'IRL Homekit - *' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\IRLHomekit'
if (Test-Path $key) { Remove-Item $key -Force }
Write-Host '  firewall rules and app entry removed'
# The relay tunnel (docs/RELAY.md), if there is one. WireGuard itself stays installed (Settings > Apps to remove it).
if (Get-Service 'WireGuardTunnel$irlhk' -ErrorAction SilentlyContinue) {
    & "$env:ProgramFiles\WireGuard\wireguard.exe" /uninstalltunnelservice irlhk
    Write-Host '  relay tunnel removed (WireGuard stays installed; remove it in Settings > Apps if you don''t use it)'
}
# Router ports IRL Homekit opened itself (they'd close within 2 hours anyway). Ones you forwarded by hand stay.
if (Test-Path "$InstallDir\scripts\Set-IRLPortMap.ps1") {
    try { $pm = & "$InstallDir\scripts\Set-IRLPortMap.ps1" -InstallDir $InstallDir -Remove -Quiet; Write-Host "  $($pm.message)" } catch { }
}

# 4. Files.
if ($wipe) {
    Set-Location $env:TEMP
    Start-Sleep -Seconds 2
    Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction Continue
    Write-Host "  deleted $InstallDir"
} else {
    Write-Host "  kept $InstallDir (delete it yourself whenever you like)"
}
Write-Host "`nIRL Homekit is uninstalled. If you forwarded ports on your router by hand, remove those forwards (or delete the relay VM if you made one)." -ForegroundColor Green
if (-not $Yes) { Read-Host 'Press Enter to close' }
