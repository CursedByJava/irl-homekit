# IRL Homekit status: what is running, whether the phone is connected, and the phone settings.
$root = Split-Path $PSScriptRoot -Parent
$s = Get-Content "$root\secrets.json" -Raw | ConvertFrom-Json
$settings = Get-Content "$root\settings.json" -Raw | ConvertFrom-Json

Write-Host "`n== Processes" -ForegroundColor Cyan
$names = @('obs64', 'mediamtx', 'go-irl', 'noalbs'); if (Test-Path "$root\caddy\Caddyfile") { $names += 'caddy' }
foreach ($p in $names) {
    # Only IRL Homekit's own OBS counts (your normal OBS may be open too).
    $proc = Get-Process -Name $p -ErrorAction SilentlyContinue | Where-Object { $p -ne 'obs64' -or $_.Path -eq (Join-Path $settings.obsDir 'obs64.exe') }
    $label = if ($p -eq 'obs64') { 'IRL OBS' } else { $p }
    if ($proc) { Write-Host ("  OK    {0,-9} running since {1}" -f $label, @($proc)[0].StartTime) -ForegroundColor Green }
    else { Write-Host ("  DOWN  {0}" -f $label) -ForegroundColor Red }
}
if (-not (Get-Process obs64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Join-Path $settings.obsDir 'obs64.exe') })) {
    Write-Host '  IRL Homekit is closed. Open it from the Start menu or the desktop icon "IRL Homekit".' -ForegroundColor Yellow
}

Write-Host "`n== Phone connection" -ForegroundColor Cyan
try {
    $path = Invoke-RestMethod 'http://127.0.0.1:9997/v3/paths/get/live' -TimeoutSec 3
    Write-Host ("  Backup (MediaMTX): publishing from {0}, ready={1}" -f $path.source.type, $path.ready) -ForegroundColor Green
} catch { Write-Host '  Backup (MediaMTX): no phone connected' }
$goirl = Get-Content "$root\logs\go-irl.err.log" -Tail 3 -ErrorAction SilentlyContinue
if ($goirl) { Write-Host '  go-irl last log lines:'; $goirl | ForEach-Object { "    $_" } }

Write-Host "`n== Public IP" -ForegroundColor Cyan
try {
    $ip = (Invoke-RestMethod 'https://api.ipify.org' -TimeoutSec 5).Trim()
    $duck = if ($settings.duckdnsName -and $s.duckdnsToken) { "$($settings.duckdnsName).duckdns.org" }
    if ($ip -ne $s.publicIp -and $duck) { Write-Host "  $ip (changed since install; $duck follows it automatically)" -ForegroundColor Green }
    elseif ($ip -ne $s.publicIp) { Write-Host "  CHANGED: now $ip (phone settings use $($s.publicIp)) - update IRL Pro and your DNS records, or use DuckDNS (docs\DOMAIN.md)" -ForegroundColor Yellow }
    else { Write-Host "  $ip (unchanged)" -ForegroundColor Green }
} catch { Write-Host '  could not check (no internet?)' -ForegroundColor Red }

Write-Host "`n== IRL Pro settings" -ForegroundColor Cyan
Write-Host "  Bonded (main):  srtla://$($s.publicIp):5000   passphrase: $($s.goirlPassphrase)"
Write-Host "  Backup SRT:     srt://$($s.publicIp):8890   stream id: publish:live:$($s.mediamtxUser):$($s.mediamtxPass)"
Write-Host "  Backup RTMP:    rtmp://$($s.publicIp):1935/live?user=$($s.mediamtxUser)&pass=$($s.mediamtxPass)"
Write-Host "`nLogs: $root\logs"
