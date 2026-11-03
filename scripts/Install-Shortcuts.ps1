# Sets up how IRL Homekit is opened. Run as administrator (the installer does this for you).
#
# IRL Homekit runs as administrator, which gives OBS priority on the graphics card (fewer skipped frames while the
# PC is busy). To do that without a permission prompt every time, it's opened through two Windows tasks that
# run with highest privileges:
#   "IRL Homekit"            opened by the Start menu / desktop shortcuts
#   "IRL Homekit (sign-in)"  opens it minimized when you sign in; enabled or disabled by -AutoStart On|Off
#                            (the dashboard's "Start with Windows" switch) - leave -AutoStart out to keep the choice
# The shortcuts (with the app icon): "IRL Homekit" in the Start menu and on the desktop, and the tools (Status,
# Update scenes, ...) in the Start menu folder "IRL Homekit". Type "IRL" in Start to find them.
param(
    [string] $InstallDir = (Split-Path $PSScriptRoot -Parent),
    [ValidateSet('', 'On', 'Off')] [string] $AutoStart = '',
    # Only change start-at-sign-in (the dashboard's "Start with Windows" switch uses this).
    [switch] $OnlyAutoStart
)
$ErrorActionPreference = 'Stop'
$appTask = 'IRL Homekit'; $signinTask = 'IRL Homekit (sign-in)'
$app = "$InstallDir\scripts\Start-IRLHomekit.ps1"

function Set-AutoStart($on) {
    $t = Get-ScheduledTask -TaskName $signinTask -ErrorAction SilentlyContinue
    if (-not $t) { return }
    if ($on) { $t | Enable-ScheduledTask | Out-Null } else { $t | Disable-ScheduledTask | Out-Null }
}
# Older versions used a Startup-folder shortcut instead of the sign-in task.
$oldStartup = Join-Path ([Environment]::GetFolderPath('Startup')) 'IRL Homekit.lnk'
if (Test-Path -LiteralPath $oldStartup) { Remove-Item -LiteralPath $oldStartup -Force }

if ($OnlyAutoStart) { if ($AutoStart) { Set-AutoStart ($AutoStart -eq 'On') }; return }

# ---- the two tasks
$user = "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
$set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances Parallel   # a second launch brings the running app's window forward
$run = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$app`""
$wasOn = (Get-ScheduledTask -TaskName $signinTask -ErrorAction SilentlyContinue).State -notin $null, 'Disabled'
Register-ScheduledTask -TaskName $appTask -Description 'Opens IRL Homekit as administrator (Start menu / desktop shortcut).' `
    -Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $run) -Settings $set -Principal $principal -Force | Out-Null
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user; $trigger.Delay = 'PT20S'
Register-ScheduledTask -TaskName $signinTask -Description 'Opens IRL Homekit (minimized) when you sign in. Turn off on the dashboard: Home PC > Start with Windows.' `
    -Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "$run -Background") -Trigger $trigger -Settings $set -Principal $principal -Force | Out-Null
Set-AutoStart $(if ($AutoStart) { $AutoStart -eq 'On' } else { $wasOn })

# ---- shortcuts
$folder = Join-Path ([Environment]::GetFolderPath('Programs')) 'IRL Homekit'
$desktop = [Environment]::GetFolderPath('Desktop')
$icon = Join-Path $InstallDir 'dashboard\public\icon.ico'
$sh = New-Object -ComObject WScript.Shell
New-Item -ItemType Directory -Force $folder | Out-Null

function New-Link($path, $target, $arguments, $description, [switch] $Minimized) {
    $l = $sh.CreateShortcut($path)
    $l.TargetPath = $target; $l.Arguments = $arguments; $l.WorkingDirectory = "$InstallDir\scripts"; $l.Description = $description
    if ($Minimized) { $l.WindowStyle = 7 }   # no console window flashing up
    if (Test-Path $icon) { $l.IconLocation = "$icon,0" }
    $l.Save()
}
$open = 'Open IRL Homekit: its own OBS plus the phone receivers and dashboard. Close the OBS window to stop everything.'
foreach ($p in (Join-Path $folder 'IRL Homekit.lnk'), (Join-Path $desktop 'IRL Homekit.lnk')) {
    New-Link $p "$env:WINDIR\System32\schtasks.exe" "/run /tn `"$appTask`"" $open -Minimized
}
$tools = [ordered]@{
    'Status'            = @('Status-IRLHomekit', "What's running, is the phone connected, your phone settings")
    'Update scenes'     = @('Update-IRLScenes', 'Rebuild the IRL scenes after you change your normal OBS scenes')
    'Import from OBS'   = @('Import-ObsSettings', 'Copy profiles, scene collections, settings and plugins from your regular OBS')
    'Set up remote dashboard' = @('Setup-RemoteDashboard', 'Reach your dashboard from your phone anywhere: no account needed (or a DuckDNS name or your own domain), with checks')
    'Change login'      = @('Set-DashboardLogin', 'Change the dashboard and Studio username or password')
    'Check for updates' = @('Update-IRLHomekit', 'See if there is a newer IRL Homekit and install it')
    'Save diagnostics'  = @('Save-Diagnostics', 'Save logs and settings (no passwords) to attach to a bug report')
    'Uninstall'         = @('Uninstall-IRLHomekit', 'Remove IRL Homekit from this PC')
}
foreach ($name in $tools.Keys) {
    New-Link (Join-Path $folder "IRL Homekit - $name.lnk") 'powershell.exe' "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$InstallDir\scripts\$($tools[$name][0]).ps1`"" $tools[$name][1]
}
# Small windows, no console.
New-Link (Join-Path $folder 'IRL Homekit - Connect Twitch.lnk') 'powershell.exe' "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$InstallDir\scripts\Connect-Twitch.ps1`"" `
    'Sign in with Twitch: stream key, chat commands, Studio and clips in one step' -Minimized
New-Link (Join-Path $folder 'IRL Homekit - Connect my phone.lnk') 'powershell.exe' "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$InstallDir\scripts\Show-PhoneQr.ps1`"" `
    'A QR code to scan with your phone: opens the dashboard signed in, then one tap sets up IRL Pro' -Minimized
New-Link (Join-Path $folder 'IRL Homekit - Dashboard address.lnk') 'powershell.exe' "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$InstallDir\scripts\Show-DashboardAddress.ps1`"" `
    'Where your dashboard is, with Copy and Open buttons, to get it onto your phone' -Minimized

# Older versions put every tool on the desktop, and had Pause / Resume.
foreach ($name in 'Status', 'Pause', 'Resume', 'Update scenes', 'Twitch chat token', 'Change login') {
    $old = Join-Path $desktop "IRL Homekit - $name.lnk"; if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force }
}
foreach ($name in 'Pause', 'Resume', 'Twitch chat token') {   # 'Twitch chat token' is now 'Connect Twitch'
    $old = Join-Path $folder "IRL Homekit - $name.lnk"; if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force }
}
$on = (Get-ScheduledTask -TaskName $signinTask).State -ne 'Disabled'
Write-Host "IRL Homekit is in the Start menu and on the desktop (runs as administrator). Opens at sign-in: $(if ($on) { 'yes' } else { 'no' })"
