# IRL Homekit status: what is running, whether the phone is connected, and the phone settings.
$root = Split-Path $PSScriptRoot -Parent
$s = Get-Content "$root\secrets.json" -Raw | ConvertFrom-Json
$settings = Get-Content "$root\settings.json" -Raw | ConvertFrom-Json

Write-Host "`n== Dashboard" -ForegroundColor Cyan
if ($settings.domain) { Write-Host "  https://$($settings.domain)   (on your phone: type it in the browser's address bar)" -ForegroundColor Green }
else { Write-Host '  http://localhost:8090   (this PC only; Start menu > IRL Homekit - Set up remote dashboard for your phone)' }
Write-Host '  Copy it, or see it any time: Start menu > IRL Homekit - Dashboard address'

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

if ($settings.relayHost) {
    Write-Host "`n== Relay ($($settings.relayHost))" -ForegroundColor Cyan
    # The tunnel (WireGuard service, scripts\Set-IRLRelay.ps1) is up when the relay answers at its tunnel address.
    $wg = Get-Service 'WireGuardTunnel$irlhk' -ErrorAction SilentlyContinue
    if (-not $wg) { Write-Host '  NOT set up: the relay tunnel is missing. Run Setup again (or Set-IRLRelay.ps1 as administrator).' -ForegroundColor Red }
    elseif ($wg.Status -ne 'Running') { Write-Host "  NOT connected: the relay tunnel is $($wg.Status.ToString().ToLower()). Open IRL Homekit (it starts it) or restart the PC." -ForegroundColor Red }
    elseif (Test-Connection 10.66.66.1 -Count 2 -Quiet) { Write-Host '  connected: the phone and dashboard come in through the relay' -ForegroundColor Green }
    else { Write-Host '  NOT connected: the relay doesn''t answer. Check the VM is running and its security list lets UDP 51820 in (docs\RELAY.md).' -ForegroundColor Red }
}

if (-not $settings.relayHost -and "$($settings.portMap)" -ne 'Off') {
    Write-Host "`n== Router ports (automatic)" -ForegroundColor Cyan
    # Opened by the app itself (scripts\Set-IRLPortMap.ps1), renewed every 20 minutes while it runs.
    $pm = try { Get-Content "$root\logs\portmap.json" -Raw | ConvertFrom-Json } catch { $null }
    if (-not $pm) { Write-Host '  not checked yet (open IRL Homekit)' -ForegroundColor Yellow }
    else {
        Write-Host "  $($pm.message)" -ForegroundColor $(if ($pm.ok) { 'Green' } elseif ($pm.problem -eq 'unsupported') { 'Yellow' } else { 'Red' })
        foreach ($p in @($pm.ports)) { Write-Host ("    {0,-3} {1,-5} {2}" -f $p.proto, $p.port, $p.note) -ForegroundColor $(if ($p.ok) { 'Gray' } else { 'Red' }) }
        Write-Host "  (checked $(([datetime]$pm.time).ToString('g')))" -ForegroundColor DarkGray
    }
}

Write-Host "`n== Public IP" -ForegroundColor Cyan
# The phone connects to the DuckDNS name if there is one (it follows the home IP, or the relay), else to the relay,
# else to the home IP as it is now. Same rule as the personal guide (PHONE-SETUP.md) and the dashboard's Phone settings card.
$duck = if ($settings.duckdnsName -and $s.duckdnsToken) { "$($settings.duckdnsName).duckdns.org" }
$ip = $null
try {
    $ip = (Invoke-RestMethod 'https://api.ipify.org' -TimeoutSec 5).Trim()
    if ($settings.relayHost) { Write-Host "  $ip (doesn't matter: the phone connects to the relay)" -ForegroundColor Green }
    elseif ($ip -ne $s.publicIp -and $duck) { Write-Host "  $ip (changed since install; $duck follows it automatically)" -ForegroundColor Green }
    elseif ($ip -ne $s.publicIp) { Write-Host "  CHANGED: now $ip (was $($s.publicIp) at install) - put the new address below into IRL Pro and update your DNS records, or use DuckDNS (docs\DOMAIN.md)" -ForegroundColor Yellow }
    else { Write-Host "  $ip (unchanged)" -ForegroundColor Green }
} catch { Write-Host '  could not check (no internet?)' -ForegroundColor Red }
$phoneHost = if ($duck) { $duck } elseif ($settings.relayHost) { $settings.relayHost } elseif ($ip) { $ip } else { $s.publicIp }

Write-Host "`n== IRL Pro settings" -ForegroundColor Cyan
if (-not $duck -and -not $settings.relayHost -and -not $ip) { Write-Host "  (could not check the current IP; showing the one from install: $($s.publicIp))" -ForegroundColor Yellow }
# The router may use another outside port for a phone port another device already had (Set-IRLPortMap.ps1).
$ext = @{ 'UDP 5000' = 5000; 'UDP 8890' = 8890; 'TCP 1935' = 1935 }
if (-not $settings.relayHost) {
    $pmx = try { Get-Content "$root\logs\portmap.json" -Raw | ConvertFrom-Json } catch { $null }
    foreach ($p in @($pmx.ports)) { $k = "$($p.proto) $($p.port)"; if ($ext.ContainsKey($k) -and $p.ok -and $p.external) { $ext[$k] = [int]$p.external } }
}
Write-Host "  Bonded (main):  srtla://${phoneHost}:$($ext['UDP 5000'])   passphrase: $($s.goirlPassphrase)"
Write-Host "  Backup SRT:     srt://${phoneHost}:$($ext['UDP 8890'])   stream id: publish:live:$($s.mediamtxUser):$($s.mediamtxPass)"
Write-Host "  Backup RTMP:    rtmp://${phoneHost}:$($ext['TCP 1935'])/live?user=$($s.mediamtxUser)&pass=$($s.mediamtxPass)"
Write-Host '  Quickest on the phone: dashboard > Phone settings > Show > Open in IRL Pro.'
Write-Host "`nLogs: $root\logs"
