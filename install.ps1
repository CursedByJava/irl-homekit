<#
IRL Homekit installer — turn a Windows PC into a self-hosted IRL streaming box (an IRL Toolkit alternative).

Run from an elevated PowerShell (Run as administrator), with OBS closed:
    powershell -ExecutionPolicy Bypass -File .\install.ps1

It asks a few questions, then:
  1. Downloads pinned, checksum-verified releases of go-irl, MediaMTX, NOALBS, obs-multi-rtmp and Caddy.
  2. Generates random passwords (secrets.json) and writes every config.
  3. Creates an OBS profile + scene collection named "IRL Homekit" (your existing ones are not touched).
  4. Turns on OBS WebSocket, installs the multistream plugin, sets up the remote dashboard.
  5. Adds firewall rules, stops the PC sleeping, and creates a logon task that keeps everything running.
  6. Writes PHONE-SETUP.md in the install folder with your personal IRL Pro settings.
Re-running it is safe: existing passwords are kept.
#>
param(
    [string] $InstallDir = 'C:\IRLHomekit',
    [string] $TwitchChannel = '',
    [string] $Domain = '',
    [string] $BaseCollection = '',
    [string] $BaseProfile = '',
    [string] $ObsName = 'IRL Homekit',
    [string] $ObsDir = 'C:\Program Files\obs-studio\bin\64bit',
    [string] $ObsConfigDir = "$env:APPDATA\obs-studio",
    [string[]] $OverlaySources = @(),
    [string] $BrbBackground = '',
    [string] $KickChannel = '',
    [string] $YoutubeChannelId = '',
    # For testing into a sandbox: skip firewall, power, scheduled task, shortcuts, plugin install and starting things.
    [switch] $SkipSystem,
    [switch] $NonInteractive
)
$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
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
Step 0 'Checking this PC'
if (-not $SkipSystem) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw 'Run this from an elevated PowerShell (right-click PowerShell > Run as administrator).' }
}
if (-not (Test-Path "$ObsDir\obs64.exe")) { throw "OBS Studio not found in $ObsDir. Install OBS 30+ from https://obsproject.com, or pass -ObsDir." }
$node = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
if (-not $node) { throw 'Node.js not found (needed for the dashboard). Install it with:  winget install OpenJS.NodeJS.LTS  then open a new PowerShell and re-run.' }
if ([int]((& $node --version) -replace '^v(\d+).*', '$1') -lt 22) { throw 'Node.js 22 or newer is required. Update with:  winget upgrade OpenJS.NodeJS.LTS' }
if (-not $SkipSystem -and (Get-Process obs64 -ErrorAction SilentlyContinue)) { throw 'Close OBS first (it overwrites its settings on exit), then re-run.' }
Info "OBS: $ObsDir  |  Node: $node"

# ------------------------------------------------------------------ questions
$scenesDir = Join-Path $ObsConfigDir 'basic\scenes'
$collections = @(Get-ChildItem $scenesDir -Filter *.json -ErrorAction SilentlyContinue | ForEach-Object {
    try { (Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).name } catch { } } | Where-Object { $_ -and $_ -ne $ObsName })
$profiles = @(Get-ChildItem (Join-Path $ObsConfigDir 'basic\profiles') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    (Get-Content "$($_.FullName)\basic.ini" -ErrorAction SilentlyContinue | Where-Object { $_ -like 'Name=*' } | Select-Object -First 1) -replace '^Name=' } | Where-Object { $_ -and $_ -ne $ObsName })

if (-not $TwitchChannel) { $TwitchChannel = Ask 'Your Twitch channel name (used for chat commands)' }
if (-not $BaseCollection -and $collections) {
    Info ('Your OBS scene collections: ' + ($collections -join ', '))
    $BaseCollection = Ask 'Copy which collection for your overlays/scenes? (Enter = start empty)'
}
if (-not $BaseProfile -and $profiles) {
    Info ('Your OBS profiles: ' + ($profiles -join ', '))
    $BaseProfile = Ask 'Copy output/stream settings from which profile? (Enter = fresh 1080p60 8000 kbps)'
}
if ($BaseCollection -and -not $OverlaySources) {
    $browser = @((Get-ChildItem $scenesDir -Filter *.json | ForEach-Object { Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } |
        Where-Object name -eq $BaseCollection | Select-Object -First 1).sources | Where-Object id -eq 'browser_source' | ForEach-Object name)
    if ($browser) {
        Info ('Browser sources in that collection: ' + ($browser -join ', '))
        $o = Ask 'Show which of them on the IRL scenes? (comma separated, Enter = none)'
        if ($o) { $OverlaySources = $o -split '\s*,\s*' }
    }
}
if (-not $KickChannel) { $KickChannel = Ask 'Your Kick channel name (Enter = same as Twitch, or none)' $TwitchChannel }
if (-not $YoutubeChannelId) { $YoutubeChannelId = Ask 'Your YouTube channel ID, starts with UC (Enter = skip)' }
if (-not $Domain) { $Domain = Ask 'Domain/subdomain for the remote dashboard, e.g. irl.example.com (Enter = local only)' }

# ------------------------------------------------------------------ 1. downloads
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
    Expand-Archive $zip $dest -Force
    # NOALBS zips its files inside a versioned folder; flatten it.
    Get-ChildItem $dest -Directory -Filter 'noalbs-v*' | ForEach-Object { Get-ChildItem $_.FullName -Force | Move-Item -Destination $dest -Force; Remove-Item $_.FullName -Force }
    Info "$($d.Name): ok"
}
Get-ChildItem $InstallDir -Recurse -File | Unblock-File

# ------------------------------------------------------------------ 2. files, secrets, settings
Step 2 'Writing scripts, passwords and settings'
Copy-Item "$repo\scripts\*.ps1" "$InstallDir\scripts\" -Force
Copy-Item "$repo\dashboard\server.mjs" "$InstallDir\dashboard\" -Force
Copy-Item "$repo\dashboard\public\*" "$InstallDir\dashboard\public\" -Recurse -Force
Copy-Item "$repo\tools" "$InstallDir\" -Recurse -Force

$secretsFile = "$InstallDir\secrets.json"
$s = if (Test-Path $secretsFile) { Get-Content $secretsFile -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
foreach ($k in @{ goirlPassphrase = 20; mediamtxPass = 16; obsWebsocketPassword = 24; dashboardPassword = 16 }.GetEnumerator()) {
    if (-not $s.($k.Key)) { $s | Add-Member -Force $k.Key (New-Secret $k.Value) }
}
if (-not $s.mediamtxUser) { $s | Add-Member -Force mediamtxUser 'irl' }
if (-not $s.dashboardUser) { $s | Add-Member -Force dashboardUser ($(if ($TwitchChannel) { $TwitchChannel.ToLower() } else { 'admin' })) }
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
    obsDir = $ObsDir; obsProfile = $ObsName; obsCollection = $ObsName; domain = $Domain; twitchChannel = $TwitchChannel.ToLower()
    phoneInputs = @('IRL Phone (Bonded)', 'IRL Phone (Backup)'); overlayInputs = @($OverlaySources); audioInputs = $audio
    autoScenes = @('IRL LIVE', 'IRL LOW', 'IRL BRB', 'IRL LIVE (Backup)', 'IRL LOW (Backup)')
    studioDomain = $(if ($Domain) { 'studio.' + ($Domain -replace '^[^.]+\.', '') } else { '' }); baseCollection = $BaseCollection; brbBackground = $BrbBackground; kickChannel = $KickChannel.ToLower(); youtubeChannelId = $YoutubeChannelId
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
$cfg = [IO.File]::ReadAllText("$repo\templates\noalbs.config.json").Replace('{{TWITCH_CHANNEL}}', $TwitchChannel.ToLower()).Replace('{{OBS_WS_PASSWORD}}', $s.obsWebsocketPassword)
$cfg = $cfg.Replace('"{{STARTING_SCENE}}"', (& $sceneOrNull $starting)).Replace('"{{ENDING_SCENE}}"', (& $sceneOrNull $ending))
$noalbsCfg = "$InstallDir\noalbs\config.json"
if ((Test-Path $noalbsCfg) -and -not (Test-Path "$noalbsCfg.original")) { Copy-Item $noalbsCfg "$noalbsCfg.original" }
$null = $cfg | ConvertFrom-Json; Write-Utf8 $noalbsCfg $cfg
Write-Utf8 "$InstallDir\noalbs\chat-block.json" ([IO.File]::ReadAllText("$repo\templates\noalbs.chat.json").Replace('{{TWITCH_CHANNEL}}', $TwitchChannel.ToLower()))
if (-not $s.twitchBotToken) { Write-Utf8 "$InstallDir\noalbs\.env" "# Filled in by scripts\Set-TwitchBotToken.ps1`nLOG_DIR=$InstallDir\logs`n" }

# ------------------------------------------------------------------ 5. OBS
Step 5 "Creating OBS profile + scene collection '$ObsName'"
$profDir = Join-Path $ObsConfigDir ('basic\profiles\' + ($ObsName -replace '[^A-Za-z0-9_\-]', '_'))
New-Item -ItemType Directory -Force $profDir | Out-Null
$baseProfDir = if ($BaseProfile) { Get-ChildItem (Join-Path $ObsConfigDir 'basic\profiles') -Directory | Where-Object { (Get-Content "$($_.FullName)\basic.ini" -ErrorAction SilentlyContinue) -contains "Name=$BaseProfile" } | Select-Object -First 1 }
if ($baseProfDir) {
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

& "$repo\scripts\New-IRLScenes.ps1" -Name $ObsName -BaseCollection $BaseCollection -ObsConfigDir $ObsConfigDir `
    -OverlaySources $OverlaySources -BrbBackground $BrbBackground -Force

$wsCfg = Join-Path $ObsConfigDir 'plugin_config\obs-websocket\config.json'
New-Item -ItemType Directory -Force (Split-Path $wsCfg) | Out-Null
$ws = if (Test-Path $wsCfg) { Get-Content $wsCfg -Raw | ConvertFrom-Json } else { [pscustomobject]@{ alerts_enabled = $false; first_load = $false } }
foreach ($kv in @{ server_enabled = $true; auth_required = $true; server_password = $s.obsWebsocketPassword; server_port = 4455 }.GetEnumerator()) { $ws | Add-Member -Force $kv.Key $kv.Value }
Write-Utf8 $wsCfg ($ws | ConvertTo-Json)
Info 'OBS WebSocket enabled on port 4455 (password in secrets.json)'

# ------------------------------------------------------------------ 6. dashboard + Caddy
Step 6 'Setting up the remote dashboard'
$env:IRLHK_PW = $s.dashboardPassword
& $node -e "const c=require('crypto');const s=c.randomBytes(16);const h=c.scryptSync(process.env.IRLHK_PW,s,64);require('fs').writeFileSync(process.argv[1],JSON.stringify({username:process.argv[2],passwordHash:s.toString('hex')+':'+h.toString('hex'),port:8090},null,2))" "$InstallDir\dashboard\config.json" $s.dashboardUser
$env:IRLHK_PW = $null
if ($Domain) {
    Write-Utf8 "$InstallDir\caddy\Caddyfile" ([IO.File]::ReadAllText("$repo\templates\Caddyfile").Replace('{{INSTALL_DIR}}', ($InstallDir -replace '\\', '/')).Replace('{{DOMAIN}}', $Domain + ', studio.' + ($Domain -replace '^[^.]+\.', '')))
    Info "HTTPS dashboard: https://$Domain and Studio: https://studio.$($Domain -replace '^[^.]+\.', '') (needs DNS A records for both -> $public and router ports 80/443)"
} else {
    Remove-Item "$InstallDir\caddy\Caddyfile" -ErrorAction SilentlyContinue
    Info 'Dashboard: http://localhost:8090 (local only; re-run with -Domain to put it online)'
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

    $plug = 'C:\ProgramData\obs-studio\plugins\obs-multi-rtmp'
    New-Item -ItemType Directory -Force "$plug\bin\64bit", "$plug\data" | Out-Null
    Copy-Item "$InstallDir\_downloads\multi-rtmp\obs-plugins\64bit\obs-multi-rtmp.dll" "$plug\bin\64bit\" -Force
    Copy-Item "$InstallDir\_downloads\multi-rtmp\data\obs-plugins\obs-multi-rtmp\*" "$plug\data\" -Recurse -Force
    Info 'obs-multi-rtmp plugin installed'

    $user = "$env:USERDOMAIN\$env:USERNAME"
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$InstallDir\scripts\Start-IRLHomekit.ps1`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user; $trigger.Delay = 'PT20S'
    # Safety net: re-run every 5 minutes; the watchdog's mutex makes extra starts exit immediately.
    $every = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName 'IRL Homekit' -Action $action -Trigger @($trigger, $every) -Settings $set -Principal $principal -Force | Out-Null
    Info "scheduled task 'IRL Homekit' runs at sign-in"

    $desktop = [Environment]::GetFolderPath('Desktop'); $sh = New-Object -ComObject WScript.Shell
    foreach ($n in @(@('Status', 'Status-IRLHomekit'), @('Pause', 'Pause-IRLHomekit'), @('Resume', 'Resume-IRLHomekit'), @('Twitch chat token', 'Set-TwitchBotToken'), @('Update scenes', 'Update-IRLScenes'))) {
        $l = $sh.CreateShortcut("$desktop\IRL Homekit - $($n[0]).lnk"); $l.TargetPath = 'powershell.exe'
        $l.Arguments = "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$InstallDir\scripts\$($n[1]).ps1`""; $l.WorkingDirectory = "$InstallDir\scripts"; $l.Save()
    }
    Info 'desktop shortcuts created'
}

# ------------------------------------------------------------------ 8. personal guide
Step 8 'Writing your personal phone guide'
$guide = [IO.File]::ReadAllText("$repo\docs\PHONE-SETUP.md")
$dash = if ($Domain) { "https://$Domain" } else { 'http://localhost:8090 (on this PC only)' }
foreach ($kv in ([ordered]@{ '{{PUBLIC_IP}}' = $(if ($public) { $public } else { '<your public IP>' }); '{{LAN_IP}}' = $lan; '{{GOIRL_PASSPHRASE}}' = $s.goirlPassphrase
    '{{MEDIAMTX_USER}}' = $s.mediamtxUser; '{{MEDIAMTX_PASS}}' = $s.mediamtxPass; '{{DASHBOARD_URL}}' = $dash; '{{DASHBOARD_USER}}' = $s.dashboardUser
    '{{DASHBOARD_PASS}}' = $s.dashboardPassword; '{{INSTALL_DIR}}' = $InstallDir }).GetEnumerator()) { $guide = $guide.Replace($kv.Key, $kv.Value) }
Write-Utf8 "$InstallDir\PHONE-SETUP.md" $guide

if (-not $SkipSystem) { Remove-Item "$InstallDir\PAUSE" -ErrorAction SilentlyContinue; Start-ScheduledTask -TaskName 'IRL Homekit' }

Write-Host "`nDone." -ForegroundColor Green
Write-Host "Your phone settings, passwords and the remaining steps (router port forwarding, auto sign-in) are in:"
Write-Host "    $InstallDir\PHONE-SETUP.md" -ForegroundColor Yellow
