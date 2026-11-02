# IRL Homekit self-test: sends fake phone streams into this PC and checks that OBS switches scenes.
# Needs ffmpeg (winget install Gyan.FFmpeg). Does NOT start your stream; nothing goes to Twitch/Kick/YouTube.
#   powershell -ExecutionPolicy Bypass -File C:\IRLHomekit\tools\Test-IRLHomekit.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$s = Get-Content "$root\secrets.json" -Raw | ConvertFrom-Json
$tmp = Join-Path $env:TEMP 'irlhk-test'; New-Item -ItemType Directory -Force $tmp | Out-Null
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { throw 'ffmpeg not found. Install it with: winget install Gyan.FFmpeg (then open a new PowerShell).' }

function Get-ObsScene {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.ConnectAsync([uri]'ws://127.0.0.1:4455', [Threading.CancellationToken]::None).Wait()
    $recv = { $buf = New-Object byte[] 65536; $seg = New-Object ArraySegment[byte] (, $buf)
        $r = $ws.ReceiveAsync($seg, [Threading.CancellationToken]::None).Result; [Text.Encoding]::UTF8.GetString($buf, 0, $r.Count) | ConvertFrom-Json }
    $send = { param($o) $b = [Text.Encoding]::UTF8.GetBytes(($o | ConvertTo-Json -Depth 5 -Compress)); $ws.SendAsync((New-Object ArraySegment[byte] (, $b)), 'Text', $true, [Threading.CancellationToken]::None).Wait() }
    $sha = { param($t) [Convert]::ToBase64String([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($t))) }
    $hello = & $recv
    $auth = & $sha ((& $sha ($s.obsWebsocketPassword + $hello.d.authentication.salt)) + $hello.d.authentication.challenge)
    & $send @{ op = 1; d = @{ rpcVersion = 1; authentication = $auth; eventSubscriptions = 0 } }; $null = & $recv
    & $send @{ op = 6; d = @{ requestType = 'GetCurrentProgramScene'; requestId = '1'; requestData = @{} } }
    $scene = (& $recv).d.responseData.currentProgramSceneName; $ws.Dispose(); $scene
}
function Wait-Scene($want, $seconds) {
    $end = (Get-Date).AddSeconds($seconds)
    do { $cur = Get-ObsScene; if ($cur -eq $want) { return $true }; Start-Sleep 2 } while ((Get-Date) -lt $end)
    Write-Host "      still on '$cur'" -ForegroundColor DarkYellow; $false
}
function Start-Ffmpeg($url, $kbps, $seconds, $log) {
    Start-Process ffmpeg -WindowStyle Hidden -PassThru -RedirectStandardError "$tmp\$log" -ArgumentList @('-hide_banner', '-re',
        '-f', 'lavfi', '-i', 'testsrc2=size=1920x1080:rate=30', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000', '-t', $seconds,
        '-c:v', 'libx264', '-preset', 'veryfast', '-b:v', "${kbps}k", '-maxrate', "${kbps}k", '-bufsize', "${kbps}k", '-g', '60', '-pix_fmt', 'yuv420p',
        '-c:a', 'aac', '-b:a', '128k', '-f', 'mpegts', "`"$url`"")
}
$results = [ordered]@{}
function Check($name, $ok) { $results[$name] = $ok; Write-Host ('  {0}  {1}' -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' }) }

Write-Host "`nIRL Homekit self-test (about 2 minutes)" -ForegroundColor Cyan
Write-Host "  OBS is on: $(Get-ObsScene)"

Write-Host "`n- Backup input (plain SRT into MediaMTX)"
$p = Start-Ffmpeg "srt://127.0.0.1:8890?streamid=publish:live:$($s.mediamtxUser):$($s.mediamtxPass)&pkt_size=1316" 4000 40 'backup.log'
Check 'backup feed -> IRL LIVE (Backup)' (Wait-Scene 'IRL LIVE (Backup)' 25)
$p | Stop-Process -Force -ErrorAction SilentlyContinue
Check 'signal lost -> IRL BRB' (Wait-Scene 'IRL BRB' 20)

Write-Host "`n- Low bitrate (600 kbps)"
$p = Start-Ffmpeg "srt://127.0.0.1:8890?streamid=publish:live:$($s.mediamtxUser):$($s.mediamtxPass)&pkt_size=1316" 600 40 'low.log'
Check 'weak signal -> IRL LOW (Backup)' (Wait-Scene 'IRL LOW (Backup)' 30)
$p | Stop-Process -Force -ErrorAction SilentlyContinue
$null = Wait-Scene 'IRL BRB' 20

Write-Host "`n- Bonded input (SRTLA into go-irl, encrypted)"
$relay = Start-Process powershell.exe -WindowStyle Hidden -PassThru -RedirectStandardOutput "$tmp\relay.log" -RedirectStandardError "$tmp\relay.err" `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\srtla-test-sender.ps1`" -Seconds 60"
Start-Sleep 3
$p = Start-Ffmpeg "srt://127.0.0.1:6000?passphrase=$($s.goirlPassphrase)&pkt_size=1316&latency=2000000" 5000 45 'bonded.log'
Check 'bonded feed -> IRL LIVE' (Wait-Scene 'IRL LIVE' 30)
$p | Stop-Process -Force -ErrorAction SilentlyContinue; $relay | Stop-Process -Force -ErrorAction SilentlyContinue
Check 'signal lost -> IRL BRB' (Wait-Scene 'IRL BRB' 20)

$failed = @($results.GetEnumerator() | Where-Object { -not $_.Value }).Count
Write-Host ''
if ($failed) { Write-Host "$failed check(s) failed. Logs: $tmp and $root\logs" -ForegroundColor Red; exit 1 }
Write-Host 'All checks passed. Your PC side works; next test from your phone on mobile data.' -ForegroundColor Green
