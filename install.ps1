<#
IRL Homekit installer — turn a Windows PC into a self-hosted IRL streaming box (an IRL Toolkit alternative).

Easiest: double-click "Install IRL Homekit.cmd" in the repo folder. Or, from an elevated PowerShell:
    powershell -ExecutionPolicy Bypass -File .\install.ps1

It asks a few questions, then:
  1. Downloads pinned, checksum-verified releases of OBS Studio (IRL Homekit's own portable copy), go-irl,
     MediaMTX, NOALBS, obs-multi-rtmp and Caddy.
  2. Generates random passwords (secrets.json) and writes every config.
  3. Sets up the IRL Homekit OBS: profile + scene collection copied from your normal OBS (which is never changed),
     multistream plugin, WebSocket, and the dashboard and Studio as panels.
  4. Adds firewall rules, stops the PC sleeping, and adds IRL Homekit to the Start menu, the desktop and
     Settings > Apps (with an uninstaller). It opens by itself when you sign in unless you pass -AutoStart Off.
  5. Writes PHONE-SETUP.md in the install folder with your personal IRL Pro settings.
Re-running it is safe: existing passwords, stream keys and your start-at-sign-in choice are kept.
#>
param(
    [string] $InstallDir = 'C:\IRLHomekit',
    [string] $TwitchChannel = '',
    [string] $Domain = '',
    [string] $BaseCollection = '',
    [string] $BaseProfile = '',
    [string] $ObsName = 'IRL Homekit',
    # Your normal OBS settings, where -BaseCollection / -BaseProfile are copied from (read only).
    [string] $BaseObsConfigDir = "$env:APPDATA\obs-studio",
    # Open IRL Homekit when you sign in to Windows. New installs: On. Re-runs keep the current choice unless given.
    [ValidateSet('', 'On', 'Off')] [string] $AutoStart = '',
    # Copy everything from your regular OBS (profiles, scene collections, settings, plugins) into the IRL Homekit OBS.
    [switch] $ImportObs,
    [string[]] $OverlaySources = @(),
    [string] $BrbBackground = '',
    [string] $KickChannel = '',
    [string] $YoutubeChannelId = '',
    # Dashboard username on first install (default: your Twitch channel). The password is asked for, never passed.
    [string] $DashboardUser = '',
    # Free DuckDNS name to keep pointed at this PC's home IP (see docs/DOMAIN.md). Taken from -Domain when it's a duckdns.org name.
    [string] $DuckDnsName = '',
    [string] $DuckDnsToken = '',
    # For testing into a sandbox: skip firewall, power, scheduled task, shortcuts, plugin install and starting things.
    [switch] $SkipSystem,
    [switch] $NonInteractive
)
$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$Version = (Get-Content "$repo\VERSION" -Raw).Trim()
$utf8 = New-Object Text.UTF8Encoding $false
function Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Info($msg) { Write-Host "    $msg" }
function Ask($q, $default = '') {
    if ($NonInteractive) { return $default }
    $a = Read-Host ($(if ($default) { "$q [$default]" } else { $q }))
    if ($a) { $a.Trim() } else { $default }
}
function Write-Utf8($path, $text) { [IO.File]::WriteAllText($path, $text, $utf8) }
function New-Secret([int]$n) {
    $c = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray(); $b = New-Object byte[] $n
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); -join ($b | ForEach-Object { $c[$_ % $c.Length] })
}

# Pinned downloads. Bump versions here; the installer refuses files whose SHA-256 doesn't match.
$Downloads = @(
    @{ Name = 'OBS Studio (IRL Homekit copy)'; Url = 'https://github.com/obsproject/obs-studio/releases/download/33.0.1/OBS-Studio-33.0.1-Windows-x64.zip'
       Sha = '0d9436451c2d772b33428e3fdae9776f071895c335de17283176306fb72651d3'; Dir = 'obs' },
    @{ Name = 'go-irl'; Url = 'https://github.com/e04/go-irl/releases/download/v3.1.0/go-irl-windows-x64.zip'
       Sha = 'c3dfa136fb0018aea7f8cfca18abbe4087aa6f5e6dd2e4447b4d4f0d47b84931'; Dir = 'go-irl' },
    @{ Name = 'MediaMTX'; Url = 'https://github.com/bluenviron/mediamtx/releases/download/v1.21.3/mediamtx_v1.21.3_windows_amd64.zip'
       Sha = 'b2f5246b07cb72961df03b8d5e8cad43dc657bcf3f49a87bb031bdf22721af74'; Dir = 'mediamtx' },
    @{ Name = 'NOALBS'; Url = 'https://github.com/NOALBS/nginx-obs-automatic-low-bitrate-switching/releases/download/v2.21.0/noalbs-v2.21.0-x86_64-pc-windows-msvc.zip'
       Sha = '8d9e0175b2ec4bea7cdc1f73b49662af8295023c830a7932b94789f42b63a8ff'; Dir = 'noalbs' },
    @{ Name = 'obs-multi-rtmp'; Url = 'https://github.com/sorayuki/obs-multi-rtmp/releases/download/0.7.4.5/obs-multi-rtmp-0.7.4.5-windows-x64.zip'
       Sha = '5ddff9bedf9cf09534db6157a5c01f5eb0115ada042ad0c3fefb7ddc1e9af801'; Dir = '_downloads\multi-rtmp' },
    @{ Name = 'Caddy'; Url = 'https://github.com/caddyserver/caddy/releases/download/v2.11.7/caddy_2.11.7_windows_amd64.zip'
       Sha = '0a1edc0b799512051c57071ce0e798d3f2cf67dc98171366f1d2b326072e3b06'; Dir = 'caddy' }
)

# ------------------------------------------------------------------ 0. checks
Write-Host "IRL Homekit $Version$(if ($Version -like '*-*') { ' (beta: report problems at https://github.com/CursedByJava/irl-homekit/issues)' })" -ForegroundColor Magenta
Step 0 'Checking this PC'
if (-not $SkipSystem) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw 'Run this from an elevated PowerShell (right-click PowerShell > Run as administrator).' }
}
# Updating? Reuse the answers from last time.
$prev = if (Test-Path "$InstallDir\settings.json") { Get-Content "$InstallDir\settings.json" -Raw | ConvertFrom-Json }
if ($prev) {
    Info 'Updating your existing IRL Homekit; your previous answers are kept.'
    if (-not $TwitchChannel) { $TwitchChannel = $prev.twitchChannel }
    if (-not $Domain) { $Domain = $prev.domain }
    if (-not $BaseCollection) { $BaseCollection = $prev.baseCollection }
    if (-not $OverlaySources) { $OverlaySources = @($prev.overlayInputs | Where-Object { $_ }) }
    if (-not $BrbBackground) { $BrbBackground = $prev.brbBackground }
    if (-not $prev -and -not $KickChannel) { $KickChannel = $prev.kickChannel }
    if (-not $prev -and -not $YoutubeChannelId) { $YoutubeChannelId = $prev.youtubeChannelId }
    if (-not $DuckDnsName) { $DuckDnsName = $prev.duckdnsName }
    if ($prev.baseObsConfigDir -and -not $PSBoundParameters.ContainsKey('BaseObsConfigDir')) { $BaseObsConfigDir = $prev.baseObsConfigDir }
}
# IRL Homekit runs its own portable OBS from the install folder; your normal OBS is only read from.
$ObsDir = "$InstallDir\obs\bin\64bit"
$ObsConfigDir = "$InstallDir\obs\config\obs-studio"
$ObsWsPort = 4456   # not OBS's default 4455, so it never clashes with your normal OBS
# The dashboard needs Node.js 22+. Use the PC's own if it has one; otherwise IRL Homekit keeps a private copy in
# $InstallDir\node: the official portable zip from nodejs.org (pinned, checksum-verified), no installer, no system changes.
$node = @("$InstallDir\node\node.exe", (Get-Command node.exe -ErrorAction SilentlyContinue).Source, "$env:ProgramFiles\nodejs\node.exe") |
    Where-Object { $_ -and (Test-Path $_) -and [int]((& $_ --version) -replace '^v(\d+).*', '$1') -ge 22 } | Select-Object -First 1
if (-not $node) {
    Info 'Getting Node.js 22 (for the dashboard) from nodejs.org...'
    New-Item -ItemType Directory -Force "$InstallDir\_downloads" | Out-Null
    $nodeZip = "$InstallDir\_downloads\node-v22.23.4-win-x64.zip"
    if (-not (Test-Path $nodeZip) -or (Get-FileHash $nodeZip).Hash.ToLower() -ne 'cbc74b5e0982c9dbb41525fd8fb5dcd32fbee237863f7829072f4639a1ce5f20') {
        Invoke-WebRequest 'https://nodejs.org/dist/v22.23.4/node-v22.23.4-win-x64.zip' -OutFile $nodeZip -UseBasicParsing
    }
    if ((Get-FileHash $nodeZip).Hash.ToLower() -ne 'cbc74b5e0982c9dbb41525fd8fb5dcd32fbee237863f7829072f4639a1ce5f20') { Remove-Item $nodeZip -Force; throw 'Node.js download: checksum mismatch, refused.' }
    $tmp = "$InstallDir\_downloads\node-extract"; if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
    Expand-Archive $nodeZip $tmp -Force
    if (Test-Path "$InstallDir\node") { Remove-Item -LiteralPath "$InstallDir\node" -Recurse -Force }
    Move-Item (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName "$InstallDir\node"
    Remove-Item -LiteralPath $tmp -Recurse -Force
    $node = "$InstallDir\node\node.exe"
}
Info "Node: $node"
# Older versions had an always-on task that relaunched IRL Homekit every 5 minutes; switch it off before anything
# else, so it can't reopen things mid-update. (It's replaced by the on-demand tasks at the end.)
if (-not $SkipSystem) {
    $legacy = Get-ScheduledTask -TaskName 'IRL Homekit' -ErrorAction SilentlyContinue
    $legacyAlwaysOn = [bool]($legacy -and $legacy.Triggers)   # remembered: it means "start with Windows" was on
    if ($legacyAlwaysOn) { $legacy | Unregister-ScheduledTask -Confirm:$false; Info 'removed the old always-on task' }
}
# IRL Homekit open (or an older version, which ran in your regular OBS with the IRL profile)? It's closed for the
# update and reopened at the end. Your regular OBS itself is never closed.
$irlObs = @(Get-Process obs64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq "$ObsDir\obs64.exe" })
$oldObs = @(Get-CimInstance Win32_Process -Filter "Name='obs64.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*IRL Homekit*' -and $_.ExecutablePath -ne "$ObsDir\obs64.exe" })
if (($irlObs -or $oldObs) -and -not $SkipSystem) {
    Info 'IRL Homekit is open. It will be closed for the update and reopened when the installer finishes.'
    if ((Ask 'Make sure you are not live. Continue? (Y/n)' 'Y') -match '^n') { throw 'Nothing was changed.' }
}

# ------------------------------------------------------------------ questions
$scenesDir = Join-Path $BaseObsConfigDir 'basic\scenes'
$collections = @(Get-ChildItem $scenesDir -Filter *.json -ErrorAction SilentlyContinue | ForEach-Object {
    try { (Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).name } catch { } } | Where-Object { $_ -and $_ -ne $ObsName })
$profiles = @(Get-ChildItem (Join-Path $BaseObsConfigDir 'basic\profiles') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    (Get-Content "$($_.FullName)\basic.ini" -ErrorAction SilentlyContinue | Where-Object { $_ -like 'Name=*' } | Select-Object -First 1) -replace '^Name=' } | Where-Object { $_ -and $_ -ne $ObsName })

if (-not $TwitchChannel) { $TwitchChannel = Ask 'Your Twitch channel name (used for chat commands)' }
if (-not $prev -and -not $BaseCollection -and $collections) {
    Info ('Your OBS scene collections: ' + ($collections -join ', '))
    $BaseCollection = Ask 'Copy which collection for your overlays/scenes? (Enter = start empty)'
}
if (-not $prev -and -not $BaseProfile -and $profiles) {
    Info ('Your OBS profiles: ' + ($profiles -join ', '))
    $BaseProfile = Ask 'Copy output/stream settings from which profile? (Enter = fresh 1080p60 8000 kbps)'
}
if (-not $prev -and $BaseCollection -and -not $OverlaySources) {
    $browser = @((Get-ChildItem $scenesDir -Filter *.json | ForEach-Object { Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } |
        Where-Object name -eq $BaseCollection | Select-Object -First 1).sources | Where-Object id -eq 'browser_source' | ForEach-Object name)
    if ($browser) {
        Info ('Browser sources in that collection: ' + ($browser -join ', '))
        $o = Ask 'Show which of them on the IRL scenes? (comma separated, Enter = none)'
        if ($o) { $OverlaySources = $o -split '\s*,\s*' }
    }
}
if (-not $ImportObs -and ($collections -or $profiles) -and -not (Test-Path "$InstallDir\settings.json")) {
    Info 'IRL Homekit runs its own copy of OBS. It can start as a full copy of your regular OBS: every profile, scene'
    Info 'collection, setting and plugin (your regular OBS is not changed). Or it can start clean with just the IRL setup.'
    $ImportObs = (Ask 'Import everything from your regular OBS? (y/N)' 'N') -match '^y'
}
if (-not $prev -and -not $KickChannel) { $KickChannel = Ask 'Your Kick channel name (Enter = same as Twitch, or none)' $TwitchChannel }
if (-not $prev -and -not $YoutubeChannelId) { $YoutubeChannelId = Ask 'Your YouTube channel ID, starts with UC (Enter = skip)' }
# Remote dashboard (reach it from your phone anywhere): the guided setup runs at the end of the install, once
# IRL Homekit is open, so it can check DNS, router ports and the HTTPS certificate for you.
$setupRemote = $false
if (-not $prev -and -not $Domain -and -not $NonInteractive) {
    Info 'Remote dashboard: control IRL Homekit from your phone anywhere at https://your-name..., with free HTTPS.'
    Info 'It needs a name: a free one from DuckDNS (2 minutes) or a domain you own. A guided setup runs at the end.'
    $setupRemote = (Ask 'Set up the remote dashboard? (Y/n)' 'Y') -notmatch '^n'
}
$Domain = "$Domain".Trim().ToLower()
$oldSecrets = if (Test-Path "$InstallDir\secrets.json") { Get-Content "$InstallDir\secrets.json" -Raw | ConvertFrom-Json }
if (-not $DuckDnsName -and $Domain -match '([a-z0-9-]+)\.duckdns\.org$') { $DuckDnsName = $Matches[1] }
$DuckDnsName = ($DuckDnsName -replace '\.duckdns\.org$', '').ToLower()
if ($DuckDnsName -and -not $DuckDnsToken -and -not $oldSecrets.duckdnsToken) {
    $DuckDnsToken = Ask 'DuckDNS token (shown at the top of duckdns.org) so your name follows your home IP (Enter = skip)'
}
# Studio sits next to the dashboard: irl.example.com -> studio.example.com. A bare DuckDNS name has no siblings
# you control, so yourname.duckdns.org -> studio.yourname.duckdns.org (DuckDNS answers for every name under yours).
$studioDomain = if (-not $Domain) { '' } elseif ($Domain -match '^[a-z0-9-]+\.duckdns\.org$') { "studio.$Domain" } else { 'studio.' + ($Domain -replace '^[^.]+\.', '') }
# Dashboard login: asked on the first install only. Change it later with the "IRL Homekit - Change login" shortcut.
$login = $null
if (-not $oldSecrets.dashboardUser) {
    $defaultUser = $(if ($DashboardUser) { $DashboardUser } elseif ($TwitchChannel) { $TwitchChannel.ToLower() } else { 'admin' })
    if ($NonInteractive) { $login = [pscustomobject]@{ Username = $defaultUser; Password = (New-Secret 16); Generated = $true } }
    else {
        Info 'Choose the login for your dashboard and Studio pages.'
        $login = & "$repo\scripts\Set-DashboardLogin.ps1" -AskOnly -Username $defaultUser
    }
}
# Start at sign-in: on for new installs (so the dashboard is there when you're out), kept as-is on re-runs.
if (-not $AutoStart) {
    if (Test-Path "$InstallDir\settings.json") {
        $signin = Get-ScheduledTask -TaskName 'IRL Homekit (sign-in)' -ErrorAction SilentlyContinue
        $AutoStart = if (($signin -and $signin.State -ne 'Disabled') -or (-not $signin -and $legacyAlwaysOn)) { 'On' } else { 'Off' }
    }
    else {
        Info 'IRL Homekit can open by itself (minimized) when you sign in to Windows, so you can go live from your phone'
        Info 'any time. You can turn this off later on the dashboard (Home PC > Start with Windows).'
        $AutoStart = if ((Ask 'Open IRL Homekit automatically when you sign in? (Y/n)' 'Y') -match '^n') { 'Off' } else { 'On' }
    }
}

# ------------------------------------------------------------------ 1. downloads
if (-not $SkipSystem) {
    # Updating: close what's running from this folder first, so its files can be replaced. An older version's
    # watchdog goes first (it would relaunch everything), then its OBS. Everything restarts when the app opens.
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*Start-IRLHomekit.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($irlObs) {
        # Ask it to close like the X button, so it saves its settings; force it after 20 seconds.
        $irlObs | ForEach-Object { & taskkill.exe /PID $_.Id | Out-Null }
        $t = (Get-Date).AddSeconds(20); while ((Get-Date) -lt $t -and ($irlObs | Where-Object { -not $_.HasExited })) { Start-Sleep 1 }
        $irlObs | Where-Object { -not $_.HasExited } | Stop-Process -Force -ErrorAction SilentlyContinue
        Info 'closed IRL Homekit'
    }
    if ($oldObs) {
        $oldObs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        # A force-closed OBS leaves a crash marker that would make your regular OBS offer Safe Mode next time.
        Start-Sleep 2; Get-ChildItem "$BaseObsConfigDir\.sentinel" -Filter 'run_*' -File -ErrorAction SilentlyContinue | Remove-Item -Force
        Info 'closed the previous IRL Homekit'
    }
    Get-Process noalbs, go-irl, mediamtx, caddy -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$InstallDir\*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    $dash = (Get-NetTCPConnection -LocalPort 8090 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
    if ($dash) { Stop-Process -Id $dash -Force -ErrorAction SilentlyContinue }
    Start-Sleep 1
}Step 1 'Downloading tools (checksum-verified)'
New-Item -ItemType Directory -Force "$InstallDir\_downloads", "$InstallDir\logs", "$InstallDir\scripts", "$InstallDir\dashboard\public" | Out-Null
foreach ($d in $Downloads) {
    $zip = Join-Path "$InstallDir\_downloads" (Split-Path $d.Url -Leaf)
    if (-not (Test-Path $zip) -or (Get-FileHash $zip).Hash.ToLower() -ne $d.Sha) {
        Info "$($d.Name): downloading"
        Invoke-WebRequest $d.Url -OutFile $zip -UseBasicParsing
    }
    if ((Get-FileHash $zip).Hash.ToLower() -ne $d.Sha) { Remove-Item $zip -Force; throw "$($d.Name): checksum mismatch, download refused." }
    $dest = Join-Path $InstallDir $d.Dir
    New-Item -ItemType Directory -Force $dest | Out-Null
    Expand-Archive $zip $dest -Force
    # NOALBS zips its files inside a versioned folder; flatten it.
    Get-ChildItem $dest -Directory -Filter 'noalbs-v*' | ForEach-Object { Get-ChildItem $_.FullName -Force | Move-Item -Destination $dest -Force; Remove-Item $_.FullName -Force }
    Info "$($d.Name): ok"
}
# Windows Smart App Control can block programs that don't carry a paid publisher signature, like these open-source
# tools. Run each one once so a block is explained now, not discovered later as "not running".
$blocked = @()
foreach ($t in @(@('go-irl', "$InstallDir\go-irl\go-irl.exe", '-h'), @('MediaMTX', "$InstallDir\mediamtx\mediamtx.exe", '--help'),
                 @('NOALBS', "$InstallDir\noalbs\noalbs.exe", '--help'), @('Caddy', "$InstallDir\caddy\caddy.exe", 'version'))) {
    try {
        $p = Start-Process $t[1] -ArgumentList $t[2] -WindowStyle Hidden -PassThru -ErrorAction Stop
        if (-not $p.WaitForExit(3000)) { $p.Kill() }
    } catch { if ("$_" -match 'Application Control|blocked') { $blocked += $t[0] } }
}
if ($blocked) {
    Write-Warning "Windows Smart App Control is blocking: $($blocked -join ', ')."
    Info 'These are the open-source tools IRL Homekit runs (they are not signed with a paid certificate). Until they are'
    Info 'allowed, the phone connection and auto-switching will not work. To allow them: Windows Security >'
    Info 'App & browser control > Smart App Control settings > Off. Note: Windows does not let you turn it back on'
    Info 'without resetting Windows. More: docs\TROUBLESHOOTING.md (Smart App Control).'
}
# Portable mode keeps this OBS's settings in $InstallDir\obs\config, apart from your normal OBS.
Write-Utf8 "$InstallDir\obs\portable_mode.txt" ''
Get-ChildItem $InstallDir -Recurse -File | Unblock-File

# ------------------------------------------------------------------ 2. files, secrets, settings
Step 2 'Writing scripts, passwords and settings'
Copy-Item "$repo\scripts\*.ps1" "$InstallDir\scripts\" -Force
Copy-Item "$repo\VERSION", "$repo\CHANGELOG.md" "$InstallDir\" -Force
Copy-Item "$repo\dashboard\server.mjs" "$InstallDir\dashboard\" -Force
Copy-Item "$repo\dashboard\public\*" "$InstallDir\dashboard\public\" -Recurse -Force
Copy-Item "$repo\tools" "$InstallDir\" -Recurse -Force
Copy-Item "$repo\templates" "$InstallDir\" -Recurse -Force   # used by Setup-RemoteDashboard.ps1
# Animated Starting Soon / BRB screens and the low-bitrate banner; keep the user's own config.js on re-runs.
$hadOverlayCfg = Test-Path "$InstallDir\overlays\config.js"
New-Item -ItemType Directory -Force "$InstallDir\overlays" | Out-Null
Get-ChildItem "$repo\overlays" -File | Where-Object { $_.Name -ne 'config.js' -or -not $hadOverlayCfg } | Copy-Item -Destination "$InstallDir\overlays\" -Force
if (-not $hadOverlayCfg) { Write-Utf8 "$InstallDir\overlays\config.js" ([IO.File]::ReadAllText("$repo\overlays\config.js").Replace("channel: ''", "channel: '$($TwitchChannel -replace "'", '')'")) }

$secretsFile = "$InstallDir\secrets.json"
$s = if (Test-Path $secretsFile) { Get-Content $secretsFile -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
foreach ($k in @{ goirlPassphrase = 20; mediamtxPass = 16; obsWebsocketPassword = 24 }.GetEnumerator()) {
    if (-not $s.($k.Key)) { $s | Add-Member -Force $k.Key (New-Secret $k.Value) }
}
if (-not $s.mediamtxUser) { $s | Add-Member -Force mediamtxUser 'irl' }
if ($login) { $s | Add-Member -Force dashboardUser $login.Username; $s | Add-Member -Force dashboardPassword $login.Password }
if ($DuckDnsToken) { $s | Add-Member -Force duckdnsToken $DuckDnsToken.Trim() }
$lan = (Get-NetIPConfiguration | Where-Object IPv4DefaultGateway | Select-Object -First 1).IPv4Address.IPAddress
$public = try { (Invoke-RestMethod 'https://api.ipify.org' -TimeoutSec 10).Trim() } catch { '' }
$s | Add-Member -Force lanIp $lan; $s | Add-Member -Force publicIp $public
$s | ConvertTo-Json | Set-Content -Encoding UTF8 $secretsFile
Info "secrets.json: $secretsFile (keep it private)"

$baseJson = if ($BaseCollection) { Get-ChildItem $scenesDir -Filter *.json | ForEach-Object { Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } | Where-Object name -eq $BaseCollection | Select-Object -First 1 }
$baseScenes = @($baseJson.scene_order | ForEach-Object name)
$audio = [ordered]@{ 'IRL Phone (Bonded)' = 'Phone mic + sound (bonded feed)'; 'IRL Phone (Backup)' = 'Phone mic + sound (backup feed)' }
if ($BrbBackground) { $audio[$BrbBackground] = 'Be Right Back background' }
$settings = [ordered]@{
    obsDir = $ObsDir; obsConfigDir = $ObsConfigDir; baseObsConfigDir = $BaseObsConfigDir; obsWebsocketPort = $ObsWsPort; obsProfile = $ObsName; obsCollection = $ObsName; domain = $Domain; twitchChannel = $TwitchChannel.ToLower()
    phoneInputs = @('IRL Phone (Bonded)', 'IRL Phone (Backup)'); overlayInputs = @($OverlaySources); audioInputs = $audio
    autoScenes = @('IRL LIVE', 'IRL LOW', 'IRL BRB', 'IRL LIVE (Backup)', 'IRL LOW (Backup)')
    studioDomain = $studioDomain; duckdnsName = $DuckDnsName; baseCollection = $BaseCollection; brbBackground = $BrbBackground; kickChannel = $KickChannel.ToLower(); youtubeChannelId = $YoutubeChannelId
}
Write-Utf8 "$InstallDir\settings.json" ($settings | ConvertTo-Json -Depth 5)

# ------------------------------------------------------------------ 3. MediaMTX
Step 3 'Configuring MediaMTX (backup SRT/RTMP receiver)'
$ymlPath = "$InstallDir\mediamtx\mediamtx.yml"
if (-not (Test-Path "$ymlPath.original")) { Copy-Item $ymlPath "$ymlPath.original" }
$y = [IO.File]::ReadAllText("$ymlPath.original")
$a = $y.IndexOf("authInternalUsers:`n"); $b = $y.IndexOf('# HTTP-based authentication.')
if ($a -lt 0 -or $b -lt $a) { throw 'Unexpected mediamtx.yml layout; update install.ps1 for this MediaMTX version.' }
$auth = @"
authInternalUsers:
  # IRL Homekit: the phone publishes to path "live" with this user/password.
  - user: $($s.mediamtxUser)
    pass: $($s.mediamtxPass)
    ips: []
    permissions:
      - action: publish
        path: live
  # OBS and NOALBS on this PC read the stream and the API without a password.
  - user: any
    pass:
    ips: ["127.0.0.1", "::1"]
    permissions:
      - action: read
      - action: api
      - action: metrics

"@
$y = $y.Substring(0, $a) + $auth + $y.Substring($b)
$logPath = ($InstallDir -replace '\\', '/') + '/logs/mediamtx.log'
$rep = [ordered]@{ "logDestinations: [stdout]" = "logDestinations: [file]"; "logFile: mediamtx.log" = "logFile: $logPath"
    "`napi: false" = "`napi: true"; "apiAddress: :9997" = "apiAddress: 127.0.0.1:9997"; "`nrtsp: true" = "`nrtsp: false"
    "`nhls: true" = "`nhls: false"; "`nwebrtc: true" = "`nwebrtc: false"; "`nmoq: true" = "`nmoq: false" }
foreach ($k in $rep.Keys) {
    if (([regex]::Matches($y, [regex]::Escape($k))).Count -ne 1) { throw "mediamtx.yml: expected exactly one '$($k.Trim())'" }
    $y = $y.Replace($k, $rep[$k])
}
Write-Utf8 $ymlPath $y

# ------------------------------------------------------------------ 4. NOALBS
Step 4 'Configuring NOALBS (automatic LIVE / LOW / BRB switching)'
$sceneOrNull = { param($n) if ($n -and $baseScenes -contains $n) { '"' + $n + '"' } else { 'null' } }
$starting = @('Starting Soon', 'Starting') | Where-Object { $baseScenes -contains $_ } | Select-Object -First 1
$ending = @('Ending', 'Ending Soon', 'End') | Where-Object { $baseScenes -contains $_ } | Select-Object -First 1
$cfg = [IO.File]::ReadAllText("$repo\templates\noalbs.config.json").Replace('{{TWITCH_CHANNEL}}', $TwitchChannel.ToLower()).Replace('{{OBS_WS_PASSWORD}}', $s.obsWebsocketPassword).Replace('"{{OBS_WS_PORT}}"', "$ObsWsPort")
$cfg = $cfg.Replace('"{{STARTING_SCENE}}"', (& $sceneOrNull $starting)).Replace('"{{ENDING_SCENE}}"', (& $sceneOrNull $ending))
$noalbsCfg = "$InstallDir\noalbs\config.json"
if ((Test-Path $noalbsCfg) -and -not (Test-Path "$noalbsCfg.original")) { Copy-Item $noalbsCfg "$noalbsCfg.original" }
$null = $cfg | ConvertFrom-Json; Write-Utf8 $noalbsCfg $cfg
Write-Utf8 "$InstallDir\noalbs\chat-block.json" ([IO.File]::ReadAllText("$repo\templates\noalbs.chat.json").Replace('{{TWITCH_CHANNEL}}', $TwitchChannel.ToLower()))
if (-not $s.twitchBotToken) { Write-Utf8 "$InstallDir\noalbs\.env" "# Filled in by scripts\Set-TwitchBotToken.ps1`nLOG_DIR=$InstallDir\logs`n" }

# ------------------------------------------------------------------ 5. OBS
Step 5 "Setting up the IRL Homekit OBS (profile + scene collection '$ObsName')"
$profDir = Join-Path $ObsConfigDir ('basic\profiles\' + ($ObsName -replace '[^A-Za-z0-9_\-]', '_'))
$hadProfile = Test-Path "$profDir\basic.ini"
New-Item -ItemType Directory -Force $profDir | Out-Null
$baseProfDir = if ($BaseProfile) { Get-ChildItem (Join-Path $BaseObsConfigDir 'basic\profiles') -Directory | Where-Object { (Get-Content "$($_.FullName)\basic.ini" -ErrorAction SilentlyContinue) -contains "Name=$BaseProfile" } | Select-Object -First 1 }
# Updating from an older version, which kept the IRL Homekit profile in your regular OBS: move it over as-is
# (stream key, encoder settings, Kick/YouTube multistream targets).
$oldIrlProfile = Join-Path $BaseObsConfigDir ('basic\profiles\' + (Split-Path $profDir -Leaf))
if (-not $hadProfile -and -not $baseProfDir -and (Test-Path "$oldIrlProfile\basic.ini")) {
    Copy-Item "$oldIrlProfile\*" $profDir -Recurse -Force; $hadProfile = $true
    Info 'brought over your existing IRL Homekit profile (stream keys and multistream targets) from your regular OBS'
}
if ($hadProfile -and -not $baseProfDir) {
    Info 'keeping the existing IRL Homekit OBS profile (stream keys and settings)'
} elseif ($baseProfDir) {
    foreach ($f in 'service.json', 'streamEncoder.json', 'recordEncoder.json') { if (Test-Path "$($baseProfDir.FullName)\$f") { Copy-Item "$($baseProfDir.FullName)\$f" $profDir -Force } }
    $out = New-Object System.Collections.Generic.List[string]; $skip = $false
    foreach ($l in Get-Content "$($baseProfDir.FullName)\basic.ini") {
        if ($l -match '^\[(.+)\]$') { $skip = $Matches[1] -in 'Twitch', 'YouTube', 'Auth' }   # don't duplicate platform logins
        if ($skip) { continue }
        if ($l -like 'Name=*') { $l = "Name=$ObsName" }
        if ($l -eq 'EnableMultitrackVideo=true') { $l = 'EnableMultitrackVideo=false' }
        $out.Add($l)
    }
    [IO.File]::WriteAllLines("$profDir\basic.ini", $out, (New-Object Text.UTF8Encoding $true))
    Info "profile copied from '$BaseProfile' (stream key included, platform login not)"
} else {
    $gpu = (Get-CimInstance Win32_VideoController).Name -join ' '
    $enc = if ($gpu -match 'NVIDIA') { 'obs_nvenc_h264_tex' } elseif ($gpu -match 'AMD|Radeon') { 'h264_texture_amf' } else { 'obs_x264' }
    $ini = @"
[General]
Name=$ObsName

[Output]
Mode=Advanced
Reconnect=true
RetryDelay=5
MaxRetries=100

[Stream1]
EnableMultitrackVideo=false

[AdvOut]
Encoder=$enc
ApplyServiceSettings=true
TrackIndex=1
AudioEncoder=ffmpeg_aac
Track1Bitrate=160

[Video]
BaseCX=1920
BaseCY=1080
OutputCX=1920
OutputCY=1080
FPSType=0
FPSCommon=60

[Audio]
SampleRate=48000
ChannelSetup=Stereo
"@
    [IO.File]::WriteAllText("$profDir\basic.ini", $ini, (New-Object Text.UTF8Encoding $true))
    Write-Utf8 "$profDir\streamEncoder.json" ('{"rate_control":"CBR","bitrate":8000,"keyint_sec":2' + $(if ($enc -eq 'obs_x264') { ',"preset":"veryfast"}' } else { ',"preset":"p5"}' }))
    Write-Utf8 "$profDir\service.json" '{"type":"rtmp_common","settings":{"service":"Twitch","server":"auto","key":""}}'
    Info "fresh profile: 1920x1080 @ 60 fps, CBR 8000 kbps, encoder $enc. Add your Twitch stream key in OBS > Settings > Stream."
}
$mr = "$profDir\obs-multi-rtmp.json"
if (-not (Test-Path $mr)) { Copy-Item "$repo\templates\obs-multi-rtmp.json" $mr }

& "$repo\scripts\New-IRLScenes.ps1" -Name $ObsName -BaseCollection $BaseCollection -ObsConfigDir $ObsConfigDir -BaseConfigDir $BaseObsConfigDir `
    -OverlayDir "$InstallDir\overlays" -OverlaySources $OverlaySources -BrbBackground $BrbBackground -Force

$wsCfg = Join-Path $ObsConfigDir 'plugin_config\obs-websocket\config.json'
New-Item -ItemType Directory -Force (Split-Path $wsCfg) | Out-Null
$ws = if (Test-Path $wsCfg) { Get-Content $wsCfg -Raw | ConvertFrom-Json } else { [pscustomobject]@{ alerts_enabled = $false; first_load = $false } }
foreach ($kv in @{ server_enabled = $true; auth_required = $true; server_password = $s.obsWebsocketPassword; server_port = $ObsWsPort }.GetEnumerator()) { $ws | Add-Member -Force $kv.Key $kv.Value }
Write-Utf8 $wsCfg ($ws | ConvertTo-Json)
Info "OBS WebSocket enabled on port $ObsWsPort (password in secrets.json)"

if ($ImportObs) { & "$repo\scripts\Import-ObsSettings.ps1" -InstallDir $InstallDir -From $BaseObsConfigDir -Yes }
# First start straight into the IRL profile, no setup wizard, with the dashboard and Studio as panels inside OBS.
& "$repo\scripts\Set-ObsUserIni.ps1" -ConfigDir $ObsConfigDir -ObsName $ObsName
Info 'dashboard and Studio are panels in the IRL Homekit OBS (Docks menu)'

# The IRL Homekit skin (OBS's default theme in IRL Homekit colours).
Copy-Item "$repo\templates\IRL_Homekit.ovt" "$InstallDir\obs\data\obs-studio\themes\" -Force
# Multistream plugin, installed into this OBS only.
New-Item -ItemType Directory -Force "$InstallDir\obs\obs-plugins\64bit", "$InstallDir\obs\data\obs-plugins\obs-multi-rtmp" | Out-Null
Copy-Item "$InstallDir\_downloads\multi-rtmp\obs-plugins\64bit\obs-multi-rtmp.dll" "$InstallDir\obs\obs-plugins\64bit\" -Force
Copy-Item "$InstallDir\_downloads\multi-rtmp\data\obs-plugins\obs-multi-rtmp\*" "$InstallDir\obs\data\obs-plugins\obs-multi-rtmp\" -Recurse -Force
Info 'obs-multi-rtmp plugin installed'

# ------------------------------------------------------------------ 6. dashboard + Caddy
Step 6 'Setting up the remote dashboard'
& "$InstallDir\scripts\Set-DashboardLogin.ps1" -InstallDir $InstallDir -Username $s.dashboardUser -Password $s.dashboardPassword -Quiet
Info "dashboard login: user $($s.dashboardUser)"
if ($Domain) {
    Write-Utf8 "$InstallDir\caddy\Caddyfile" ([IO.File]::ReadAllText("$repo\templates\Caddyfile").Replace('{{INSTALL_DIR}}', ($InstallDir -replace '\\', '/')).Replace('{{DOMAIN}}', "$Domain, $studioDomain"))
    if ($DuckDnsName -and $s.duckdnsToken) {
        # Point the DuckDNS name at this PC now, so the HTTPS certificate can be issued on first start.
        $r = try { Invoke-RestMethod "https://www.duckdns.org/update?domains=$DuckDnsName&token=$($s.duckdnsToken)" -TimeoutSec 15 } catch { "error: $($_.Exception.Message)" }
        if ($r -eq 'OK') { Info "DuckDNS: $DuckDnsName.duckdns.org now points at this PC (kept up to date every 5 minutes)" }
        else { Write-Warning "DuckDNS update failed ($r). Check the token and name at duckdns.org, then re-run with -DuckDnsToken." }
        Info "HTTPS dashboard: https://$Domain and Studio: https://$studioDomain (needs router ports 80/443)"
    } else {
        Info "HTTPS dashboard: https://$Domain and Studio: https://$studioDomain (needs DNS records for both -> $public and router ports 80/443, see docs\DOMAIN.md)"
    }
} else {
    Remove-Item "$InstallDir\caddy\Caddyfile" -ErrorAction SilentlyContinue
    Info 'Dashboard: http://localhost:8090 (this PC only; Start menu > IRL Homekit - Set up remote dashboard puts it online)'
}

# ------------------------------------------------------------------ 7. system
if ($SkipSystem) {
    Step 7 'Skipping firewall / power / task / plugin install (-SkipSystem)'
} else {
    Step 7 'Firewall, power, multistream plugin, autostart'
    $rules = @(
        @{ Name = 'IRL Homekit - go-irl SRTLA (UDP 5000)'; Program = "$InstallDir\go-irl\go-irl.exe"; Protocol = 'UDP'; Port = 5000 },
        @{ Name = 'IRL Homekit - MediaMTX SRT (UDP 8890)'; Program = "$InstallDir\mediamtx\mediamtx.exe"; Protocol = 'UDP'; Port = 8890 },
        @{ Name = 'IRL Homekit - MediaMTX RTMP (TCP 1935)'; Program = "$InstallDir\mediamtx\mediamtx.exe"; Protocol = 'TCP'; Port = 1935 })
    if ($Domain) {
        $rules += @{ Name = 'IRL Homekit - Dashboard HTTPS (TCP 443)'; Program = "$InstallDir\caddy\caddy.exe"; Protocol = 'TCP'; Port = 443 }
        $rules += @{ Name = 'IRL Homekit - Dashboard HTTP (TCP 80)'; Program = "$InstallDir\caddy\caddy.exe"; Protocol = 'TCP'; Port = 80 }
    }
    foreach ($r in $rules) {
        Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        New-NetFirewallRule -DisplayName $r.Name -Direction Inbound -Action Allow -Program $r.Program -Protocol $r.Protocol -LocalPort $r.Port -Profile Any | Out-Null
    }
    Info 'firewall rules added'
    powercfg /change standby-timeout-ac 0; powercfg /change hibernate-timeout-ac 0; powercfg /change monitor-timeout-ac 15
    Info 'sleep and hibernate disabled while plugged in'

    # Runs as administrator (better OBS performance) through two Windows tasks, so there's no prompt each time.
    # This also replaces the always-on task older versions used.
    & "$InstallDir\scripts\Install-Shortcuts.ps1" -InstallDir $InstallDir -AutoStart $AutoStart | Out-Null
    Info "IRL Homekit added to the Start menu and desktop (runs as administrator); opens at sign-in: $AutoStart"

    # Settings > Apps entry with an uninstaller.
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\IRLHomekit'
    New-Item -Force $key | Out-Null
    $uninstall = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\scripts\Uninstall-IRLHomekit.ps1`""
    foreach ($kv in ([ordered]@{ DisplayName = 'IRL Homekit'; DisplayVersion = $Version; Publisher = 'IRL Homekit'
        DisplayIcon = "$InstallDir\dashboard\public\icon.ico"; InstallLocation = $InstallDir; UninstallString = $uninstall
        URLInfoAbout = 'https://github.com/CursedByJava/irl-homekit' }).GetEnumerator()) { Set-ItemProperty $key $kv.Key $kv.Value }
    Set-ItemProperty $key NoModify 1 -Type DWord; Set-ItemProperty $key NoRepair 1 -Type DWord
    Info 'listed in Settings > Apps (uninstall from there)'
}

# ------------------------------------------------------------------ 8. personal guide
Step 8 'Writing your personal phone guide'
$guide = [IO.File]::ReadAllText("$repo\docs\PHONE-SETUP.md")
$dash = if ($Domain) { "https://$Domain" } else { 'http://localhost:8090 (on this PC only)' }
foreach ($kv in ([ordered]@{ '{{PUBLIC_IP}}' = $(if ($public) { $public } else { '<your public IP>' }); '{{LAN_IP}}' = $lan; '{{GOIRL_PASSPHRASE}}' = $s.goirlPassphrase
    '{{MEDIAMTX_USER}}' = $s.mediamtxUser; '{{MEDIAMTX_PASS}}' = $s.mediamtxPass; '{{DASHBOARD_URL}}' = $dash; '{{DASHBOARD_USER}}' = $s.dashboardUser
    '{{STUDIO_URL}}' = $(if ($Domain) { "https://$studioDomain" } else { 'http://localhost:8090/studio (on this PC only)' })
    '{{PHONE_HOST}}' = $(if ($DuckDnsName -and $s.duckdnsToken) { "$DuckDnsName.duckdns.org" } elseif ($public) { $public } else { '<your public IP>' })
    '{{DASHBOARD_PASS}}' = $s.dashboardPassword; '{{INSTALL_DIR}}' = $InstallDir }).GetEnumerator()) { $guide = $guide.Replace($kv.Key, $kv.Value) }
Write-Utf8 "$InstallDir\PHONE-SETUP.md" $guide

if (-not $SkipSystem) {
    Start-ScheduledTask -TaskName 'IRL Homekit'
    if ($setupRemote) { Step 9 'Remote dashboard'; & "$InstallDir\scripts\Setup-RemoteDashboard.ps1" -InstallDir $InstallDir }
}

Write-Host "`nDone.$(if (-not $SkipSystem) { ' IRL Homekit is opening.' })" -ForegroundColor Green
Write-Host "    Open it any time from the Start menu or the desktop icon 'IRL Homekit'. Close its OBS window to stop it."
Write-Host "    Opens by itself when you sign in: $AutoStart (change it on the dashboard: Home PC > Start with Windows)."
Write-Host "`nSign in to your dashboard:" -ForegroundColor Cyan
Write-Host "    Dashboard  $dash"
if ($Domain) { Write-Host "    Studio     https://$studioDomain" }
Write-Host "    Username   $($s.dashboardUser)"
Write-Host "    Password   $(if ($login -and $login.Generated) { $s.dashboardPassword } elseif ($login) { '(the one you chose)' } else { '(unchanged)' })"
Write-Host "    Change it any time: Start menu > IRL Homekit - Change login."
Write-Host "`nYour phone settings, passwords and the remaining steps (router port forwarding, auto sign-in) are in:"
Write-Host "    $InstallDir\PHONE-SETUP.md" -ForegroundColor Yellow
Write-Host "`nEnjoying IRL Homekit? It's free; if you'd like to chip in: https://github.com/CursedByJava/irl-homekit#support-the-project" -ForegroundColor DarkGray
