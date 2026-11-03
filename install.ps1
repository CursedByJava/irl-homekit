<#
IRL Homekit installer — turn a Windows PC into a self-hosted IRL streaming box (an IRL Toolkit alternative).

Easiest: run IRL-Homekit-Setup.exe from the Releases page (a normal Windows setup wizard; it runs this script for
you). Or double-click "Install IRL Homekit.cmd" in the repo folder, or from an elevated PowerShell:
    powershell -ExecutionPolicy Bypass -File .\install.ps1

It asks a few questions (none with -NonInteractive, which is what Setup.exe and the updater use), then:
  1. Downloads pinned, checksum-verified releases of OBS Studio (IRL Homekit's own portable copy), go-irl,
     MediaMTX, NOALBS, obs-multi-rtmp and Caddy.
  2. Generates random passwords (secrets.json) and writes every config.
  3. Sets up the IRL Homekit OBS: profile + scene collection copied from your normal OBS (which is never changed),
     multistream plugin, WebSocket, and the dashboard and Studio as panels.
  4. Adds firewall rules, stops the PC sleeping, and adds IRL Homekit to the Start menu, the desktop and
     Settings > Apps (with an uninstaller). It opens by itself when you sign in unless you pass -AutoStart Off.
  5. Writes PHONE-SETUP.md in the install folder with your personal IRL Pro settings.
  6. Asks your router to open the phone's ports by itself (UPnP / NAT-PMP, scripts\Set-IRLPortMap.ps1), so most
     people need no port forwarding; it says so when the router can't (then: forward them by hand, docs/ROUTER.md).
     With -RelayHost it connects to your relay server instead (a free cloud VM, docs/RELAY.md): for internet
     providers that share one public address between homes (carrier-grade NAT), where nothing else works.
Secrets are never passed on the command line: Setup.exe hands them over in environment variables
(IRLHK_DASHBOARD_PASSWORD, IRLHK_DUCKDNS_TOKEN, IRLHK_RELAY_TOKEN).
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
    # Channels are all optional: leave them empty to add them later (run Setup again). 'none' removes one on an update.
    [string] $KickChannel = '',
    # Your YouTube channel: its ID (UC...), its link, or its @handle.
    [string] $YoutubeChannelId = '',
    # Your own extra destination (any RTMP server: Restream, Facebook, your own...), streamed to alongside the others.
    # Its stream key comes from the environment (IRLHK_CUSTOM_KEY), never the command line. -CustomServer off removes it.
    [string] $CustomName = '',
    [string] $CustomServer = '',
    # Dashboard username on first install (default: your Twitch channel). The password is asked for, never passed.
    [string] $DashboardUser = '',
    # Free DuckDNS name to keep pointed at this PC's home IP (see docs/DOMAIN.md). Taken from -Domain when it's a duckdns.org name.
    [string] $DuckDnsName = '',
    [string] $DuckDnsToken = '',
    # Public IP (or name) of your relay server, so your router needs no port forwarding (docs/RELAY.md). 'off' turns it off.
    [string] $RelayHost = '',
    # Open the phone's ports on your router automatically (UPnP / NAT-PMP). New installs: Auto. Re-runs keep the choice.
    [ValidateSet('', 'Auto', 'Off')] [string] $PortMap = '',
    # Setup.exe: write a summary of the result (key<TAB>value lines) to this file at the end.
    [string] $ResultFile = '',
    # Setup.exe: the wizard's answers (JSON, UTF-8), same names as these parameters. Avoids command-line quoting.
    [string] $AnswersFile = '',
    # For testing into a sandbox: skip firewall, power, scheduled task, shortcuts, plugin install and starting things.
    [switch] $SkipSystem,
    [switch] $NonInteractive
)
$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
if ($AnswersFile) {
    $answers = [IO.File]::ReadAllText($AnswersFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($p in $answers.PSObject.Properties) {
        if ($PSBoundParameters.ContainsKey($p.Name)) { continue }   # the command line wins
        switch ($p.Name) {
            { $_ -in 'ImportObs', 'NonInteractive' } { Set-Variable $p.Name ([switch][bool]$p.Value); break }
            'OverlaySources' { $OverlaySources = @($p.Value | Where-Object { $_ }); break }
            { $_ -in 'InstallDir', 'TwitchChannel', 'Domain', 'BaseCollection', 'BaseProfile', 'AutoStart', 'KickChannel', 'YoutubeChannelId',
                'DashboardUser', 'DuckDnsName', 'RelayHost', 'BrbBackground', 'CustomName', 'CustomServer', 'PortMap' } { Set-Variable $p.Name ([string]$p.Value); break }
            default { Write-Warning "answers file: ignoring unknown setting '$($p.Name)'" }
        }
    }
}
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
# Secrets from Setup.exe (environment, so they never show up in the process list).
if (-not $DuckDnsToken -and $env:IRLHK_DUCKDNS_TOKEN) { $DuckDnsToken = $env:IRLHK_DUCKDNS_TOKEN }
# Signed in with Twitch in Setup.exe (scripts\Connect-Twitch.ps1): the path of the result file; used in step 5.
$twitchAuth = if ($env:IRLHK_TWITCH_AUTH -and (Test-Path -LiteralPath $env:IRLHK_TWITCH_AUTH)) { $env:IRLHK_TWITCH_AUTH } else { '' }
if ($twitchAuth) { $TwitchChannel = (Get-Content -LiteralPath $twitchAuth -Raw | ConvertFrom-Json).login }
# The relay's address as an IP (DuckDNS and DNS records need one, even if you entered a name).
function Resolve-RelayIp($h) {
    if (-not $h) { return '' }
    if ($h -match '^\d{1,3}(\.\d{1,3}){3}$') { return $h }
    try { ([Net.Dns]::GetHostAddresses($h) | Where-Object AddressFamily -eq 'InterNetwork' | Select-Object -First 1).IPAddressToString } catch { '' }
}
$result = [ordered]@{ ok = $false; version = ''; warnings = @() }
# Setup.exe shows this script's output live; send it as UTF-8 so dashes and quotes come through.
if ($ResultFile) { try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false } catch { } }
# Windows PowerShell's download progress bar slows big downloads (OBS) down a lot when nobody is watching it.
if ($NonInteractive -or $ResultFile) { $ProgressPreference = 'SilentlyContinue' }

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
# With a relay server (docs/RELAY.md), scripts\Set-IRLRelay.ps1 also installs WireGuard (pinned there).

# ------------------------------------------------------------------ 0. checks
$result.version = $Version
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
    if (-not $KickChannel) { $KickChannel = $prev.kickChannel }
    if (-not $YoutubeChannelId) { $YoutubeChannelId = $prev.youtubeChannelId }
    if (-not $DuckDnsName) { $DuckDnsName = $prev.duckdnsName }
    if (-not $RelayHost) { $RelayHost = $prev.relayHost }
    if (-not $PortMap) { $PortMap = $prev.portMap }
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

if (-not $prev -and -not $TwitchChannel) { $TwitchChannel = Ask 'Your Twitch channel name, for chat commands (Enter = skip, add it later)' }
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
if (-not $prev -and -not $YoutubeChannelId) { $YoutubeChannelId = Ask 'Your YouTube channel: link, @handle or ID (Enter = skip)' }
foreach ($n in 'TwitchChannel', 'KickChannel', 'YoutubeChannelId') { if ((Get-Variable $n -ValueOnly) -eq 'none') { Set-Variable $n '' } }
$TwitchChannel = "$TwitchChannel".Trim() -replace '^(https?://)?(www\.)?twitch\.tv/', '' -replace '[/?].*$', ''
$KickChannel = "$KickChannel".Trim() -replace '^(https?://)?(www\.)?kick\.com/', '' -replace '[/?].*$', ''
if ("$CustomServer".Trim() -and "$CustomServer".Trim() -ne 'off' -and "$CustomServer".Trim() -notmatch '^rtmps?://[^\s/]+') { throw "Custom destination '$CustomServer' isn't an RTMP address (rtmp://... or rtmps://...)." }
# YouTube: a link or @handle becomes the channel ID (UC...), read from the channel page's canonical link.
$YoutubeChannelId = "$YoutubeChannelId".Trim()
if ($YoutubeChannelId -and $YoutubeChannelId -notmatch '^UC[\w-]{22}$') {
    $ytId = [regex]::Match($YoutubeChannelId, 'youtube\.com/channel/(UC[\w-]{22})').Groups[1].Value
    if (-not $ytId) {
        $ytUrl = if ($YoutubeChannelId -match '^https?://') { $YoutubeChannelId } elseif ($YoutubeChannelId -match '^@') { "https://www.youtube.com/$YoutubeChannelId" } else { "https://www.youtube.com/@$YoutubeChannelId" }
        try {
            $page = (Invoke-WebRequest $ytUrl -UseBasicParsing -TimeoutSec 20 -Headers @{ 'Accept-Language' = 'en-US' } -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)').Content
            $ytId = [regex]::Match($page, '<link rel="canonical" href="https://www\.youtube\.com/channel/(UC[\w-]{22})"').Groups[1].Value
        } catch { }
    }
    if ($ytId) { Info "YouTube channel: $ytId"; $YoutubeChannelId = $ytId }
    else {
        $m = "Couldn't find the YouTube channel '$YoutubeChannelId', so it was skipped. Add it later by running Setup again (paste your channel's link)."
        $result.warnings += $m; Write-Warning $m; $YoutubeChannelId = ''
    }
}
# Remote dashboard (reach it from your phone anywhere): the guided setup runs at the end of the install, once
# IRL Homekit is open, so it can check DNS, router ports and the HTTPS certificate for you.
$setupRemote = $false
if (-not $prev -and -not $Domain -and -not $NonInteractive) {
    Info 'Remote dashboard: control IRL Homekit from your phone anywhere at https://your-name..., with free HTTPS.'
    Info 'It needs a name: a free one from DuckDNS (2 minutes) or a domain you own. A guided setup runs at the end.'
    $setupRemote = (Ask 'Set up the remote dashboard? (Y/n)' 'Y') -notmatch '^n'
}
$Domain = "$Domain".Trim().ToLower()
if ($Domain -eq 'off') { $Domain = '' }   # Setup.exe: remote dashboard switched off
if ($DuckDnsName -eq 'off') { $DuckDnsName = '' }   # Setup.exe: no DuckDNS name any more
$oldSecrets = if (Test-Path "$InstallDir\secrets.json") { Get-Content "$InstallDir\secrets.json" -Raw | ConvertFrom-Json }
if (-not $DuckDnsName -and $Domain -match '([a-z0-9-]+)\.duckdns\.org$') { $DuckDnsName = $Matches[1] }
$DuckDnsName = ($DuckDnsName -replace '\.duckdns\.org$', '').ToLower()
if ($DuckDnsName -and -not $DuckDnsToken -and -not $oldSecrets.duckdnsToken) {
    $DuckDnsToken = Ask 'DuckDNS token (shown at the top of duckdns.org) so your name follows your home IP (Enter = skip)'
}
# Studio sits next to the dashboard: irl.example.com -> studio.example.com. A bare DuckDNS name has no siblings
# you control, so yourname.duckdns.org -> studio.yourname.duckdns.org (DuckDNS answers for every name under yours).
if (-not $PortMap) { $PortMap = 'Auto' }
$RelayHost = "$RelayHost".Trim().ToLower() -replace '^[a-z]+://', '' -replace '[:/].*$', ''
if ($RelayHost -eq 'off') { $RelayHost = '' }
if ($RelayHost -and $RelayHost -notmatch '^(\d{1,3}(\.\d{1,3}){3}|[a-z0-9-]+(\.[a-z0-9-]+)+)$') { throw "Relay server '$RelayHost' is not an IP address or host name." }
$studioDomain = if (-not $Domain) { '' } elseif ($Domain -match '^[a-z0-9-]+\.duckdns\.org$') { "studio.$Domain" } else { 'studio.' + ($Domain -replace '^[^.]+\.', '') }
# Dashboard login: asked on the first install only. Change it later with the "IRL Homekit - Change login" shortcut.
$login = $null
if (-not $oldSecrets.dashboardUser) {
    $defaultUser = $(if ($DashboardUser) { $DashboardUser } elseif ($TwitchChannel) { $TwitchChannel.ToLower() } else { 'admin' })
    if ($NonInteractive -and $env:IRLHK_DASHBOARD_PASSWORD) { $login = [pscustomobject]@{ Username = $defaultUser; Password = $env:IRLHK_DASHBOARD_PASSWORD; Generated = $false } }
    elseif ($NonInteractive) { $login = [pscustomobject]@{ Username = $defaultUser; Password = (New-Secret 16); Generated = $true } }
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
        # A crashed OBS can be held open by Windows Error Reporting while it writes a crash report; end that too.
        foreach ($o in $irlObs | Where-Object { -not $_.HasExited }) {
            Get-CimInstance Win32_Process -Filter "Name='WerFault.exe'" | Where-Object { $_.CommandLine -match "-p $($o.Id)\b" } |
                ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            & taskkill.exe /F /T /PID $o.Id | Out-Null
        }
        $t = (Get-Date).AddSeconds(10); while ((Get-Date) -lt $t -and ($irlObs | Where-Object { -not $_.HasExited })) { Start-Sleep 1 }
        if ($irlObs | Where-Object { -not $_.HasExited }) { throw 'The IRL Homekit OBS is stuck and won''t close. Close its window (or restart the PC), then run the installer again.' }
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
}
Step 1 'Downloading tools (checksum-verified)'
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
    # Already unpacked at this exact version (updates): leave it, so nothing in use needs replacing.
    $marker = Join-Path $dest '.irlhk-version'
    if ((Test-Path $marker) -and (Get-Content $marker -Raw).Trim() -eq $d.Sha) { Info "$($d.Name): up to date"; continue }
    try { Expand-Archive $zip $dest -Force }
    catch {
        # Some files are in use (e.g. by an OBS that's stuck closing). Fine if what's there already matches the download.
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $z = [IO.Compression.ZipFile]::OpenRead($zip)
        try {
            $differs = @($z.Entries | Where-Object { $_.Name } | Where-Object {
                $f = Join-Path $dest $_.FullName; -not (Test-Path -LiteralPath $f) -or (Get-Item -LiteralPath $f).Length -ne $_.Length })
        } finally { $z.Dispose() }
        if ($differs.Count -and -not ($d.Dir -eq 'noalbs')) { throw "$($d.Name): some files are in use and couldn't be updated ($($_.Exception.Message)). Close IRL Homekit or restart the PC, then run the installer again." }
        Info "$($d.Name): files in use, but already up to date"
    }
    # NOALBS zips its files inside a versioned folder; flatten it.
    Get-ChildItem $dest -Directory -Filter 'noalbs-v*' | ForEach-Object { Get-ChildItem $_.FullName -Force | Move-Item -Destination $dest -Force; Remove-Item $_.FullName -Force }
    Write-Utf8 $marker $d.Sha
    Info "$($d.Name): ok"
}
# Windows Smart App Control can block programs that don't carry a paid publisher signature, like these open-source
# tools. Run each one once so a block is explained now, not discovered later as "not running".
$blocked = @()
foreach ($t in @(@('go-irl', "$InstallDir\go-irl\go-irl.exe", '-h'), @('MediaMTX', "$InstallDir\mediamtx\mediamtx.exe", '--help'),
                 @('NOALBS', "$InstallDir\noalbs\noalbs.exe", '--help'), @('Caddy', "$InstallDir\caddy\caddy.exe", 'version'))) {
    if (-not (Test-Path $t[1])) { continue }
    try {
        $p = Start-Process $t[1] -ArgumentList $t[2] -WindowStyle Hidden -PassThru -ErrorAction Stop
        if (-not $p.WaitForExit(3000)) { $p.Kill() }
    } catch { if ("$_" -match 'Application Control|blocked') { $blocked += $t[0] } }
}
if ($blocked) {
    $result.warnings += "Windows Smart App Control is blocking $($blocked -join ', '). To allow them: Windows Security > App & browser control > Smart App Control settings > Off."
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
# OBS's own login for reading the backup feed (nothing gets the feed just for coming from this PC).
if (-not $s.mediamtxReadUser) { $s | Add-Member -Force mediamtxReadUser 'obs' }
if (-not $s.mediamtxReadPass) { $s | Add-Member -Force mediamtxReadPass (New-Secret 16) }
if ($login) { $s | Add-Member -Force dashboardUser $login.Username; $s | Add-Member -Force dashboardPassword $login.Password }
if ($DuckDnsToken) { $s | Add-Member -Force duckdnsToken $DuckDnsToken.Trim() }
# Relay password: the same one must be in the relay VM's setup script (Setup.exe makes it before you create the VM).
if ($env:IRLHK_RELAY_TOKEN -and $env:IRLHK_RELAY_TOKEN -match '^[A-Za-z0-9]{24,64}$') { $s | Add-Member -Force relayToken $env:IRLHK_RELAY_TOKEN }
if ($RelayHost -and -not $s.relayToken) { $s | Add-Member -Force relayToken (New-Secret 32) }
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
    studioDomain = $studioDomain; duckdnsName = $DuckDnsName; relayHost = $RelayHost; portMap = $PortMap; baseCollection = $BaseCollection; brbBackground = $BrbBackground; kickChannel = $KickChannel.ToLower(); youtubeChannelId = $YoutubeChannelId
    streamTo = $(if ($prev.streamTo) { $prev.streamTo } else { [ordered]@{ twitch = $true; kick = $true; youtube = $true; custom = $true } })   # dashboard's "Stream to" switches
}
if ($prev.clips) { $settings.clips = $prev.clips }   # dashboard's Clips card

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
  # OBS reads the stream with its own login (nothing gets the feed just for coming from this PC).
  - user: $($s.mediamtxReadUser)
    pass: $($s.mediamtxReadPass)
    ips: []
    permissions:
      - action: read
        path: live
  # NOALBS and the dashboard on this PC use the API (bound to 127.0.0.1, so never reachable from outside) without a password.
  - user: any
    pass:
    ips: ["127.0.0.1", "::1"]
    permissions:
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
# NOALBS needs a name for its user even without Twitch (chat commands stay off until Twitch is connected).
$cfg = [IO.File]::ReadAllText("$repo\templates\noalbs.config.json").Replace('{{TWITCH_CHANNEL}}', $(if ($TwitchChannel) { $TwitchChannel.ToLower() } else { 'irlhomekit' })).Replace('{{OBS_WS_PASSWORD}}', $s.obsWebsocketPassword).Replace('"{{OBS_WS_PORT}}"', "$ObsWsPort")
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
# IRL Homekit starts Kick / YouTube itself, following the dashboard's "Stream to" switches, so the plugin must not
# start them on its own with the main stream (OBS is closed here, so this edit sticks).
$mrCfg = Get-Content $mr -Raw | ConvertFrom-Json
# Your own extra destination (any RTMP server) is target 1003; the dashboard shows it under "Stream to" once it has a key.
$CustomServer = "$CustomServer".Trim()
if ($CustomServer -eq 'off') {
    $mrCfg.targets = @($mrCfg.targets | Where-Object { "$($_.id)" -ne '1003' }); Info 'custom destination removed'
} elseif ($CustomServer) {
    if ($CustomServer -notmatch '^rtmps?://[^\s/]+') { throw "Custom destination '$CustomServer' isn't an RTMP address (rtmp://... or rtmps://...)." }
    $ct = @($mrCfg.targets) | Where-Object { "$($_.id)" -eq '1003' } | Select-Object -First 1
    if (-not $ct) {
        $ct = ([IO.File]::ReadAllText("$repo\templates\obs-multi-rtmp.json") | ConvertFrom-Json).targets | Where-Object { "$($_.id)" -eq '1003' }
        $mrCfg.targets = @($mrCfg.targets) + $ct
    }
    $ct.name = $(if ("$CustomName".Trim()) { "$CustomName".Trim() } elseif ($ct.name) { $ct.name } else { 'Custom' })
    $ct.'service-param'.server = $CustomServer
    if ($env:IRLHK_CUSTOM_KEY) { $ct.'service-param'.key = $env:IRLHK_CUSTOM_KEY.Trim() }
    Info "custom destination: $($ct.name) ($CustomServer)$(if (-not $ct.'service-param'.key) { ' - add its stream key in OBS > Docks > Multiple output' })"
}
foreach ($t in @($mrCfg.targets)) { $t.'sync-start' = $false; $t.'sync-stop' = $false; if ($t.'service-param'.key) { $t.enabled = $true } }
Write-Utf8 $mr ($mrCfg | ConvertTo-Json -Depth 10)

& "$repo\scripts\New-IRLScenes.ps1" -Name $ObsName -BaseCollection $BaseCollection -ObsConfigDir $ObsConfigDir -BaseConfigDir $BaseObsConfigDir `
    -OverlayDir "$InstallDir\overlays" -OverlaySources $OverlaySources -BrbBackground $BrbBackground -Force
# Twitch sign-in from Setup.exe: chat token, channel ID and stream key (into the profile written above).
if ($twitchAuth) { & "$InstallDir\scripts\Connect-Twitch.ps1" -InstallDir $InstallDir -Apply $twitchAuth }

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
$mrDll = "$InstallDir\obs\obs-plugins\64bit\obs-multi-rtmp.dll"; $mrNew = "$InstallDir\_downloads\multi-rtmp\obs-plugins\64bit\obs-multi-rtmp.dll"
# Skip when it's already this exact file (it may be loaded by an OBS that's stuck closing).
if (-not (Test-Path $mrDll) -or (Get-FileHash $mrDll).Hash -ne (Get-FileHash $mrNew).Hash) { Copy-Item $mrNew "$InstallDir\obs\obs-plugins\64bit\" -Force }
Copy-Item "$InstallDir\_downloads\multi-rtmp\data\obs-plugins\obs-multi-rtmp\*" "$InstallDir\obs\data\obs-plugins\obs-multi-rtmp\" -Recurse -Force
Info 'obs-multi-rtmp plugin installed'

# ------------------------------------------------------------------ 6. relay, dashboard + Caddy
Step 6 'Setting up the relay and the remote dashboard'
$relayIp = Resolve-RelayIp $RelayHost
if ($RelayHost) {
    New-Item -ItemType Directory -Force "$InstallDir\relay" | Out-Null
    # The VM's setup script (same token), kept here in case you need to set up the VM again.
    $vps = [IO.File]::ReadAllText("$repo\templates\relay-vps.sh").Replace("`r`n", "`n").Replace('{{RELAY_TOKEN}}', $s.relayToken).Replace('{{VERSION}}', $Version)
    Write-Utf8 "$InstallDir\relay\relay-vps.sh" $vps
    # The tunnel itself (WireGuard, scripts\Set-IRLRelay.ps1) is set up at the end, with the other system changes.
    Info "relay: phone and dashboard traffic arrives through $RelayHost (no router port forwarding needed)"
    if (-not $relayIp) { $result.warnings += "Couldn't look up the relay server '$RelayHost'. Check the address."; Write-Warning "Couldn't look up '$RelayHost'." }
}
# Behind the relay, dashboard visitors arrive from the relay's tunnel address (10.66.66.1), with their own address in
# a PROXY header added by the relay (sign-in limits are per visitor).
$caddyServers = if ($RelayHost) { "servers {`n`t`tlistener_wrappers {`n`t`t`tproxy_protocol {`n`t`t`t`ttimeout 5s`n`t`t`t`tallow 10.66.66.1/32`n`t`t`t}`n`t`t`ttls`n`t`t}`n`t}" } else { '' }
& "$InstallDir\scripts\Set-DashboardLogin.ps1" -InstallDir $InstallDir -Username $s.dashboardUser -Password $s.dashboardPassword -Quiet
Info "dashboard login: user $($s.dashboardUser)"
if ($Domain) {
    Write-Utf8 "$InstallDir\caddy\Caddyfile" ([IO.File]::ReadAllText("$repo\templates\Caddyfile").Replace('{{INSTALL_DIR}}', ($InstallDir -replace '\\', '/')).Replace('{{DOMAIN}}', "$Domain, $studioDomain").Replace('{{SERVERS}}', $caddyServers))
    if ($DuckDnsName -and $s.duckdnsToken) {
        # Point the DuckDNS name at this PC now, so the HTTPS certificate can be issued on first start.
        # With a relay, the name points at the relay (that's where phones and browsers connect), not at this PC.
        $r = try { Invoke-RestMethod "https://www.duckdns.org/update?domains=$DuckDnsName&token=$($s.duckdnsToken)$(if ($relayIp) { "&ip=$relayIp" })" -TimeoutSec 15 } catch { "error: $($_.Exception.Message)" }
        if ($r -eq 'OK') { Info "DuckDNS: $DuckDnsName.duckdns.org now points at $(if ($relayIp) { "your relay ($relayIp)" } else { 'this PC' }) (kept up to date every 5 minutes)" }
        else { $result.warnings += "DuckDNS refused the name and token ($r). Check both at duckdns.org, then run Setup again."; Write-Warning "DuckDNS update failed ($r). Check the token and name at duckdns.org, then re-run with -DuckDnsToken." }
        Info "HTTPS dashboard: https://$Domain and Studio: https://$studioDomain ($(if ($RelayHost) { 'through your relay' } else { 'needs router ports 80/443' }))"
    } else {
        $target = if ($relayIp) { "$relayIp (your relay)" } else { $public }
        Info "HTTPS dashboard: https://$Domain and Studio: https://$studioDomain (needs DNS records for both -> $target$(if (-not $RelayHost) { ' and router ports 80/443' }), see docs\DOMAIN.md)"
        $result.warnings += "Point DNS records for $Domain and $studioDomain at $target (docs\DOMAIN.md)."
    }
} else {
    Remove-Item "$InstallDir\caddy\Caddyfile" -ErrorAction SilentlyContinue
    Info 'Dashboard: http://localhost:8090 (this PC only; Start menu > IRL Homekit - Set up remote dashboard puts it online)'
}

# ------------------------------------------------------------------ 7. system
$portMapResult = $null
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
    # Router ports: opened automatically unless there's a relay (nothing comes in through the router then, so
    # anything opened before is closed again) or it's switched off.
    try { $portMapResult = & "$InstallDir\scripts\Set-IRLPortMap.ps1" -InstallDir $InstallDir -Quiet }
    catch { $portMapResult = $null; Write-Warning "Couldn't ask the router to open ports: $($_.Exception.Message)" }
    if ($portMapResult -and -not $RelayHost -and $PortMap -ne 'Off') {
        if ($portMapResult.ok) { Info $portMapResult.message }
        else { $result.warnings += $portMapResult.message; Write-Warning $portMapResult.message }
    }
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
# Outside ports for the phone: the router may have given one of them a different number (scripts\Set-IRLPortMap.ps1).
$phonePort = { param($proto, $port) $m = @($portMapResult.ports) | Where-Object { -not $RelayHost -and $_.proto -eq $proto -and [int]$_.port -eq $port -and $_.ok -and $_.external } | Select-Object -First 1
    if ($m) { [string]$m.external } else { [string]$port } }
foreach ($kv in ([ordered]@{ '{{PORT_BONDED}}' = (& $phonePort 'UDP' 5000); '{{PORT_SRT}}' = (& $phonePort 'UDP' 8890); '{{PORT_RTMP}}' = (& $phonePort 'TCP' 1935) }).GetEnumerator()) { $guide = $guide.Replace($kv.Key, $kv.Value) }
foreach ($kv in ([ordered]@{ '{{PUBLIC_IP}}' = $(if ($public) { $public } else { '<your public IP>' }); '{{LAN_IP}}' = $lan; '{{GOIRL_PASSPHRASE}}' = $s.goirlPassphrase
    '{{MEDIAMTX_USER}}' = $s.mediamtxUser; '{{MEDIAMTX_PASS}}' = $s.mediamtxPass; '{{DASHBOARD_URL}}' = $dash; '{{DASHBOARD_USER}}' = $s.dashboardUser
    '{{STUDIO_URL}}' = $(if ($Domain) { "https://$studioDomain" } else { 'http://localhost:8090/studio (on this PC only)' })
    '{{PHONE_HOST}}' = $(if ($DuckDnsName -and $s.duckdnsToken) { "$DuckDnsName.duckdns.org" } elseif ($RelayHost) { $RelayHost } elseif ($public) { $public } else { '<your public IP>' })
    '{{RELAY_HOST}}' = $RelayHost
    '{{ROUTER_PORTS}}' = $(if ($portMapResult.ok -and @($portMapResult.ports | Where-Object { $_.manual })) { "$($portMapResult.message) IRL Homekit keeps the others open while it runs. The ports:" }
        elseif ($portMapResult.ok) { "IRL Homekit opened these on your router by itself ($($portMapResult.method)) and keeps them open while it runs: nothing to do." }
        elseif ($portMapResult.message) { "$($portMapResult.message) The ports, all to this PC (``$lan``):" }
        else { "forward these to this PC (``$lan``). See ``docs/ROUTER.md`` in the IRL Homekit repo for router-by-router steps." })
    '{{ROUTER_AFTER}}' = $(if ($portMapResult.ok) { "If your phone ever can't connect from outside your home, forward them by hand to this PC (``$lan``): ``docs/ROUTER.md``." }
        else { "Also give this PC a **DHCP reservation** so it keeps ``$lan``." })
    '{{DASHBOARD_PASS}}' = $s.dashboardPassword; '{{INSTALL_DIR}}' = $InstallDir }).GetEnumerator()) { $guide = $guide.Replace($kv.Key, $kv.Value) }
# Keep the router or the relay instructions, whichever applies.
$drop = if ($RelayHost) { 'router' } else { 'relay' }
$guide = [regex]::Replace($guide, "(?s)<!-- $drop -->.*?<!-- /$drop -->\r?\n?", '')
$guide = [regex]::Replace($guide, '<!-- /?(router|relay) -->\r?\n?', '')
Write-Utf8 "$InstallDir\PHONE-SETUP.md" $guide

$relayOk = $null
if (-not $SkipSystem) {
    # The relay tunnel (WireGuard, a Windows service that starts at boot), or removing it when the relay is off.
    if ($RelayHost) { Step 9 "Connecting to your relay ($RelayHost)" }
    try {
        $r = & "$InstallDir\scripts\Set-IRLRelay.ps1" -InstallDir $InstallDir -WaitSeconds $(if ($RelayHost) { 60 } else { 0 })
        if ($RelayHost) {
            $relayOk = [bool]$r.Connected
            if ($relayOk) { Info $r.Message } else { $result.warnings += $r.Message; Write-Warning $r.Message }
        }
    } catch {
        $relayOk = $false; $msg = "Couldn't set up the relay tunnel: $($_.Exception.Message)"
        $result.warnings += $msg; Write-Warning $msg
    }
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
Write-Host "`nYour phone settings, passwords and the remaining steps ($(if ($RelayHost) { 'relay, ' } elseif (-not $portMapResult.ok) { 'router port forwarding, ' })auto sign-in) are in:"
Write-Host "    $InstallDir\PHONE-SETUP.md" -ForegroundColor Yellow
if ($ResultFile) {
    $result.ok = $true
    $result.installDir = $InstallDir; $result.guide = "$InstallDir\PHONE-SETUP.md"; $result.autoStart = $AutoStart
    $result.dashboardUrl = $dash; $result.studioUrl = $(if ($Domain) { "https://$studioDomain" } else { '' })
    $result.username = $s.dashboardUser
    $result.password = $(if ($login -and $login.Generated) { $s.dashboardPassword } else { '' })   # only one we made up
    $result.relayHost = $RelayHost; $result.relayConnected = $relayOk
    # Router ports opened automatically: True / False, with what to do about it (empty with a relay or -SkipSystem).
    $result.portMapOk = $(if ($portMapResult -and -not $RelayHost -and $PortMap -ne 'Off') { [bool]$portMapResult.ok } else { '' })
    $result.portMapProblem = "$($portMapResult.problem)"
    # key<TAB>value lines (UTF-8 with BOM), easy for Setup.exe to read; one "warning" line per warning.
    $out = foreach ($k in $result.Keys) { if ($k -eq 'warnings') { foreach ($w in $result.warnings) { "warning`t$w" } } else { "$k`t$($result[$k])" } }
    [IO.File]::WriteAllLines($ResultFile, [string[]]$out, (New-Object Text.UTF8Encoding $true))
}
Write-Host "`nEnjoying IRL Homekit? It's free; if you'd like to chip in: https://github.com/CursedByJava/irl-homekit#support-the-project" -ForegroundColor DarkGray
