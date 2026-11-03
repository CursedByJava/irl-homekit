<#
Sign in with Twitch: connects IRL Homekit to your Twitch channel in one step. Twitch opens in your browser with a
code already filled in; you click Authorize. IRL Homekit then has:
  - your channel name and ID (Studio, chat, clips on BRB),
  - a chat token for !bitrate / !start / !stop and Studio chat, which it renews by itself,
  - your stream key, put into the IRL Homekit OBS,
  - permission to change your title and category (Studio) and to play your clips as video (clips on BRB).
It uses Twitch's sign-in for devices with IRL Homekit's own Twitch app: no developer account, no token website,
nothing to copy and paste. Sign out any time: twitch.tv > Settings > Connections > IRL Homekit > Disconnect.

    Connect-Twitch.ps1                  sign in and use it in this install (Start menu > IRL Homekit - Connect Twitch)
    Connect-Twitch.ps1 -OutFile x.json  sign in only and save the result (Setup.exe, before anything is installed)
    Connect-Twitch.ps1 -Apply x.json    use a saved result in this install (install.ps1), then delete the file
#>
param(
    [string] $InstallDir = (Split-Path $PSScriptRoot -Parent),
    [string] $OutFile = '',
    [string] $Apply = ''
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
# IRL Homekit's Twitch app (dev.twitch.tv console, client type Public: no secret exists for it).
$ClientId = ''
$Scopes = 'chat:read chat:edit channel:manage:broadcast channel:manage:clips channel:read:stream_key'
$utf8 = New-Object Text.UTF8Encoding $false

function Get-TwitchError($err) {
    $m = try { ($err.ErrorDetails.Message | ConvertFrom-Json).message } catch { '' }
    if ($m) { $m } else { $err.Exception.Message }
}
function Invoke-Helix($path, $token) {
    Invoke-RestMethod "https://api.twitch.tv/helix/$path" -Headers @{ 'Client-Id' = $ClientId; Authorization = "Bearer $token" } -TimeoutSec 20
}

# ------------------------------------------------------------------ sign in (a small window with the code)
function Connect-Twitch {
    if (-not $ClientId) { throw 'Twitch sign-in is not available in this version of IRL Homekit yet.' }
    $dev = Invoke-RestMethod 'https://id.twitch.tv/oauth2/device' -Method Post -Body @{ client_id = $ClientId; scopes = $Scopes } -TimeoutSec 20
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()
    $f = New-Object Windows.Forms.Form
    $f.Text = 'Sign in with Twitch'; $f.StartPosition = 'CenterScreen'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.ClientSize = New-Object Drawing.Size 520, 300; $f.BackColor = [Drawing.Color]::FromArgb(28, 28, 30); $f.ForeColor = [Drawing.Color]::White
    $f.Font = New-Object Drawing.Font 'Segoe UI', 10; $f.TopMost = $true
    $icon = Join-Path (Split-Path $PSScriptRoot -Parent) 'dashboard\public\icon.ico'; if (Test-Path $icon) { $f.Icon = New-Object Drawing.Icon $icon }
    $label = { param($text, $y, $size, $bold) $l = New-Object Windows.Forms.Label; $l.Text = $text; $l.Location = New-Object Drawing.Point 24, $y; $l.AutoSize = $true
        $l.MaximumSize = New-Object Drawing.Size 472, 0; $l.Font = New-Object Drawing.Font 'Segoe UI', $size, $(if ($bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }); $f.Controls.Add($l); $l }
    $null = & $label 'Twitch opened in your browser. Check that it shows this code, then click Authorize:' 20 10 $false
    $code = & $label $dev.user_code 62 30 $true; $code.ForeColor = [Drawing.Color]::FromArgb(169, 112, 255)
    $status = & $label 'Waiting for you to authorize on Twitch...' 130 10 $false; $status.ForeColor = [Drawing.Color]::FromArgb(170, 170, 175)
    $null = & $label 'Not signed in to Twitch in that browser? Sign in there first; the code stays the same.' 166 9 $false
    $btn = { param($text, $x, $onClick) $b = New-Object Windows.Forms.Button; $b.Text = $text; $b.Location = New-Object Drawing.Point $x, 240; $b.Size = New-Object Drawing.Size 150, 36
        $b.FlatStyle = 'Flat'; $b.BackColor = [Drawing.Color]::FromArgb(58, 58, 60); $b.ForeColor = [Drawing.Color]::White; $b.Add_Click($onClick); $f.Controls.Add($b); $b }
    $null = & $btn 'Open Twitch again' 24 { Start-Process $dev.verification_uri }
    $cancel = & $btn 'Cancel' 346 { $f.Close() }; $f.CancelButton = $cancel

    $script:auth = $null
    $deadline = (Get-Date).AddSeconds([int]$dev.expires_in)
    $timer = New-Object Windows.Forms.Timer; $timer.Interval = [Math]::Max(2, [int]$dev.interval) * 1000
    $timer.Add_Tick({
        if ((Get-Date) -gt $deadline) { $timer.Stop(); $status.Text = 'The code ran out. Close this and try again.'; return }
        try {
            $script:auth = Invoke-RestMethod 'https://id.twitch.tv/oauth2/token' -Method Post -TimeoutSec 15 -Body @{
                client_id = $ClientId; scopes = $Scopes; device_code = $dev.device_code; grant_type = 'urn:ietf:params:oauth:grant-type:device_code' }
            $timer.Stop(); $f.Close()
        } catch {
            $m = Get-TwitchError $_
            if ($m -notmatch 'authorization_pending|slow_down') { $timer.Stop(); $status.Text = "Twitch said: $m. Close this and try again." }
        }
    })
    $f.Add_Shown({ Start-Process $dev.verification_uri; $timer.Start() })
    [void]$f.ShowDialog(); $timer.Dispose()
    if (-not $script:auth) { return $null }

    $t = $script:auth.access_token
    $u = (Invoke-Helix 'users' $t).data[0]
    $key = try { (Invoke-Helix "streams/key?broadcaster_id=$($u.id)" $t).data[0].stream_key } catch { '' }
    [ordered]@{ clientId = $ClientId; userId = $u.id; login = $u.login; displayName = $u.display_name; token = $t
        refresh = $script:auth.refresh_token; scopes = $Scopes; streamKey = $key }
}

# ------------------------------------------------------------------ use it in an install
function Use-TwitchAuth($a) {
    $settingsFile = "$InstallDir\settings.json"
    $set = Get-Content $settingsFile -Raw | ConvertFrom-Json
    $set | Add-Member -Force twitchChannel $a.login
    [IO.File]::WriteAllText($settingsFile, ($set | ConvertTo-Json -Depth 10), $utf8)
    # Chat commands (NOALBS): the same steps as a pasted token.
    & "$InstallDir\scripts\Set-TwitchBotToken.ps1" -BotUsername $a.login -Token $a.token -RefreshToken $a.refresh | Out-Null
    $s = Get-Content "$InstallDir\secrets.json" -Raw | ConvertFrom-Json
    foreach ($kv in @{ twitchAuth = 'device'; twitchClientId = $a.clientId; twitchUserId = $a.userId }.GetEnumerator()) { $s | Add-Member -Force $kv.Key $kv.Value }
    if ($a.streamKey) {
        $svc = [pscustomobject]@{ type = 'rtmp_common'; settings = [pscustomobject]@{ service = 'Twitch'; server = 'auto'; key = $a.streamKey } }
        $s | Add-Member -Force streamTwitch $svc
        # The IRL Homekit OBS profile streams to Twitch until the dashboard points it elsewhere.
        $prof = Join-Path $set.obsConfigDir ('basic\profiles\' + ("$(if ($set.obsProfile) { $set.obsProfile } else { 'IRL Homekit' })" -replace '[^A-Za-z0-9_-]', '_'))
        $svcFile = Join-Path $prof 'service.json'
        $cur = try { Get-Content $svcFile -Raw | ConvertFrom-Json } catch { $null }
        if (-not $cur -or ($cur.type -eq 'rtmp_common' -and "$($cur.settings.service)" -match 'twitch')) {
            New-Item -ItemType Directory -Force $prof | Out-Null
            [IO.File]::WriteAllText($svcFile, ($svc | ConvertTo-Json -Depth 5), $utf8)
        }
    }
    [IO.File]::WriteAllText("$InstallDir\secrets.json", ($s | ConvertTo-Json -Depth 10), $utf8)
    # The dashboard reads these at start: restart it (the app's watchdog brings it back within seconds).
    $dash = (Get-NetTCPConnection -LocalPort 8090 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
    if ($dash) { Stop-Process -Id $dash -Force -ErrorAction SilentlyContinue }
}

if ($Apply) {
    try { Use-TwitchAuth (Get-Content $Apply -Raw | ConvertFrom-Json); Write-Host "    Twitch connected: $((Get-Content $Apply -Raw | ConvertFrom-Json).login)" }
    finally { Remove-Item -LiteralPath $Apply -Force -ErrorAction SilentlyContinue }
    return
}
try { $a = Connect-Twitch } catch {
    $m = Get-TwitchError $_
    if ($OutFile) { [IO.File]::WriteAllText("$OutFile.error", $m, $utf8); exit 2 }
    Add-Type -AssemblyName System.Windows.Forms; [void][Windows.Forms.MessageBox]::Show("Couldn't sign in with Twitch: $m", 'IRL Homekit'); exit 2
}
if (-not $a) { exit 1 }   # cancelled
if ($OutFile) {
    [IO.File]::WriteAllText($OutFile, ($a | ConvertTo-Json), $utf8)
    [IO.File]::WriteAllText("$OutFile.login", $a.login, $utf8)   # for Setup.exe, which can't read JSON
    exit 0
}
Use-TwitchAuth ([pscustomobject]$a)
Add-Type -AssemblyName System.Windows.Forms
[void][Windows.Forms.MessageBox]::Show("Twitch connected as $($a.displayName).$(if ($a.streamKey) { ' Your stream key is in the IRL Homekit OBS.' }) Chat commands start working in about 15 seconds.", 'IRL Homekit')
