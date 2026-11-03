# Sets up (or changes, or turns off) the remote dashboard: opening your dashboard and Studio from your phone
# anywhere at https://your-name..., with a free HTTPS certificate. Then it checks every piece and tells you what to
# fix: DNS, router ports 80/443, and the certificate.
#   Start menu "IRL Homekit - Set up remote dashboard" (the installer also offers it)
#   -CheckOnly                                  re-run the checks for the current setup
#   -DuckDnsName me -DuckDnsToken <token>       free DuckDNS name, no questions
#   -Domain irl.example.com                     your own domain, no questions
#   -Off                                        dashboard on this PC only
param(
    [string] $InstallDir = (Split-Path $PSScriptRoot -Parent),
    [string] $DuckDnsName = '', [string] $DuckDnsToken = '', [string] $Domain = '',
    [switch] $Off, [switch] $CheckOnly
)
$ErrorActionPreference = 'Stop'

# Firewall rules need administrator rights: ask once, then continue elevated with the same choices.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $CheckOnly) {
    $pass = foreach ($k in $PSBoundParameters.Keys) { $v = $PSBoundParameters[$k]; if ($v -is [switch]) { if ($v) { "-$k" } } else { "-$k `"$v`"" } }
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$PSCommandPath`" $($pass -join ' ')"
    exit
}

$utf8 = New-Object Text.UTF8Encoding $false
$settingsFile = "$InstallDir\settings.json"; $secretsFile = "$InstallDir\secrets.json"
$settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
$secrets = Get-Content $secretsFile -Raw | ConvertFrom-Json
$interactive = -not ($DuckDnsName -or $Domain -or $Off -or $CheckOnly)
function Head($t) { Write-Host "`n$t" -ForegroundColor Cyan }
function Ok($t) { Write-Host "  OK   $t" -ForegroundColor Green }
function Bad($t) { Write-Host "  FIX  $t" -ForegroundColor Yellow }
function Say($t) { Write-Host "       $t" }
function Studio-For($d) { if ($d -match '^[a-z0-9-]+\.duckdns\.org$') { "studio.$d" } else { 'studio.' + ($d -replace '^[^.]+\.', '') } }
$public = try { (Invoke-RestMethod 'https://api.ipify.org' -TimeoutSec 10).Trim() } catch { '' }
$gateway = (Get-NetIPConfiguration | Where-Object IPv4DefaultGateway | Select-Object -First 1).IPv4DefaultGateway.NextHop
$lan = (Get-NetIPConfiguration | Where-Object IPv4DefaultGateway | Select-Object -First 1).IPv4Address.IPAddress
# With a relay server (docs/RELAY.md), names point at the relay and it brings ports 80/443 to this PC; no router setup.
$relayHost = $settings.relayHost
$relayIp = if (-not $relayHost) { '' } elseif ($relayHost -match '^\d{1,3}(\.\d{1,3}){3}$') { $relayHost } else {
    try { ([Net.Dns]::GetHostAddresses($relayHost) | Where-Object AddressFamily -eq 'InterNetwork' | Select-Object -First 1).IPAddressToString } catch { '' } }
$target = if ($relayHost) { $relayIp } else { $public }
$targetName = if ($relayHost) { "your relay ($relayIp)" } else { "your home IP ($public)" }

Write-Host "`nIRL Homekit - remote dashboard" -ForegroundColor Magenta
Write-Host "Open your dashboard and Studio from your phone anywhere, with free HTTPS."
if ($settings.domain) { Write-Host "Now: https://$($settings.domain)  (Studio: https://$($settings.studioDomain))" } else { Write-Host 'Now: this PC only (http://localhost:8090)' }

# ------------------------------------------------------------------ 1. choose
$mode = if ($Off) { 'off' } elseif ($DuckDnsName) { 'duck' } elseif ($Domain) { 'own' } elseif ($CheckOnly) { 'check' } else { '' }
if ($interactive) {
    Head 'How do you want to reach your dashboard?'
    Write-Host "  1  Free name from DuckDNS, like yourname.duckdns.org  (recommended, 2 minutes, follows your $(if ($relayHost) { 'relay' } else { 'home IP' }))"
    Write-Host '  2  A domain I own, like irl.yourname.com             (about $10/year; see docs\DOMAIN.md for cheap ones)'
    Write-Host '  3  This PC only (turn remote access off)'
    if ($settings.domain) { Write-Host '  Enter  keep the current setup and just check it' }
    $c = Read-Host 'Choose 1, 2 or 3'
    $mode = switch ($c) { '1' { 'duck' } '2' { 'own' } '3' { 'off' } default { if ($settings.domain) { 'check' } else { 'duck' } } }
}

if ($mode -eq 'duck' -and $interactive) {
    Head 'Free name from DuckDNS'
    Say '1. Your browser opens duckdns.org. Sign in (GitHub, Google, Reddit or X).'
    Say '2. Under "sub domain", type a name (letters, numbers, dashes), e.g. "willirl", and press "add domain".'
    Say '3. Copy the "token" shown at the top of the page.'
    Start-Process 'https://www.duckdns.org'
    do { $DuckDnsName = ((Read-Host 'The name you added (just the name, without .duckdns.org)') -replace '\.duckdns\.org$', '').Trim().ToLower() } until ($DuckDnsName -match '^[a-z0-9-]+$')
    while ($true) {
        $DuckDnsToken = (Read-Host 'Your DuckDNS token').Trim()
        if ($DuckDnsToken -match '^[0-9a-f-]{36}$') { break }
        Write-Host '       That does not look like a token (36 letters/numbers with dashes). Copy it again.' -ForegroundColor Yellow
    }
}
if ($mode -eq 'own' -and $interactive) {
    Head 'A domain you own'
    Say 'Use a subdomain for the dashboard, e.g. irl.yourname.com. Studio will be studio.yourname.com.'
    do { $Domain = (Read-Host 'Dashboard address').Trim().ToLower() -replace '^https?://', '' -replace '/.*$', '' } until ($Domain -match '^[a-z0-9-]+(\.[a-z0-9-]+){2,}$')
    $st = Studio-For $Domain
    Head 'Add these two records in your domain''s DNS settings'
    Write-Host ''
    Write-Host ('    Type  Name                     Value')
    Write-Host ('    A     {0,-24} {1}' -f ($Domain -replace '\..*$', ''), $(if ($target) { $target } else { '<your public IP>' }))
    Write-Host ('    A     {0,-24} {1}' -f ($st -replace '\..*$', ''), $(if ($target) { $target } else { '<your public IP>' }))
    Write-Host ''
    Say 'Where to find DNS settings:'
    Say '  GoDaddy:     My Products > your domain > DNS > Add New Record'
    Say '  Cloudflare:  your domain > DNS > Records > Add record. Set Proxy status to "DNS only" (grey cloud)!'
    Say '  Namecheap:   Domain List > Manage > Advanced DNS > Add New Record'
    Say '  Porkbun:     Domain Management > your domain > DNS'
    Say 'Tip: your home IP can change. To make it automatic, point both names (CNAME) at a free DuckDNS name: docs\DOMAIN.md.'
    [void](Read-Host "`nPress Enter once both records are saved")
}

# ------------------------------------------------------------------ 2. apply
if ($mode -in 'duck', 'own', 'off') {
    Head 'Saving'
    if ($mode -eq 'duck') {
        $r = try { Invoke-RestMethod "https://www.duckdns.org/update?domains=$DuckDnsName&token=$DuckDnsToken$(if ($relayIp) { "&ip=$relayIp" })" -TimeoutSec 15 } catch { "error: $($_.Exception.Message)" }
        if ($r -ne 'OK') { throw "DuckDNS refused that name and token ($r). Check both on duckdns.org and run this again." }
        Ok "$DuckDnsName.duckdns.org now points at $targetName; IRL Homekit keeps it up to date"
        $Domain = "$DuckDnsName.duckdns.org"
        $secrets | Add-Member -Force duckdnsToken $DuckDnsToken
    }
    $newDomain = if ($mode -eq 'off') { '' } else { $Domain }
    $settings | Add-Member -Force domain $newDomain
    $settings | Add-Member -Force studioDomain $(if ($newDomain) { Studio-For $newDomain } else { '' })
    # A DuckDNS name stays updated even with your own domain (so CNAME records pointing at it keep working).
    if ($mode -eq 'duck') { $settings | Add-Member -Force duckdnsName $DuckDnsName }
    [IO.File]::WriteAllText($settingsFile, ($settings | ConvertTo-Json -Depth 5), $utf8)
    [IO.File]::WriteAllText($secretsFile, ($secrets | ConvertTo-Json -Depth 10), $utf8)

    $caddyfile = "$InstallDir\caddy\Caddyfile"
    if ($newDomain) {
        $tpl = [IO.File]::ReadAllText("$InstallDir\templates\Caddyfile")
        $servers = if ($relayHost) { "servers {`n`t`tlistener_wrappers {`n`t`t`tproxy_protocol {`n`t`t`t`ttimeout 5s`n`t`t`t`tallow 10.66.66.1/32`n`t`t`t}`n`t`t`ttls`n`t`t}`n`t}" } else { '' }
        [IO.File]::WriteAllText($caddyfile, $tpl.Replace('{{INSTALL_DIR}}', ($InstallDir -replace '\\', '/')).Replace('{{DOMAIN}}', "$newDomain, $($settings.studioDomain)").Replace('{{SERVERS}}', $servers), $utf8)
        foreach ($p in 443, 80) {
            $name = "IRL Homekit - Dashboard HTTP$(if ($p -eq 443) { 'S' }) (TCP $p)"
            Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
            New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow -Program "$InstallDir\caddy\caddy.exe" -Protocol TCP -LocalPort $p -Profile Any | Out-Null
        }
        Ok "web server set up for https://$newDomain and https://$($settings.studioDomain)"
    } else {
        if (Test-Path $caddyfile) { Remove-Item -LiteralPath $caddyfile -Force }
        Get-NetFirewallRule -DisplayName 'IRL Homekit - Dashboard HTTP*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        Ok 'remote access turned off; the dashboard works on this PC at http://localhost:8090'
    }
    # Personal guide
    $guide = "$InstallDir\PHONE-SETUP.md"
    if (Test-Path $guide) {
        $g = [IO.File]::ReadAllText($guide)
        # Guides from beta.17 on: the address under "type:" in step 1, and the Studio line at the end.
        $newDash = if ($newDomain) { "https://$newDomain" } else { 'http://localhost:8090 (on this PC only)' }
        $newStudio = if ($newDomain) { "https://$($settings.studioDomain)" } else { 'http://localhost:8090/studio (on this PC only)' }
        $g = $g -replace '(tap the address bar at the top and type:\r?\n\r?\n    )[^\r\n]*', ('${1}' + $newDash)
        $g = $g -replace '(?m)^(Studio \(combined chat, title and category on every platform\): ).*?( \(same login\)\r?)$', ('${1}' + $newStudio + '$2')
        $g = $g -replace '(?m)^\| Dashboard \| \*\*[^*]*\*\* \|', ('| Dashboard | **' + $(if ($newDomain) { "https://$newDomain" } else { 'http://localhost:8090 (on this PC only)' }) + '** |')
        $g = $g -replace '(?m)^\| Studio \| \*\*[^*]*\*\* \|', ('| Studio | **' + $(if ($newDomain) { "https://$($settings.studioDomain)" } else { 'http://localhost:8090/studio (on this PC only)' }) + '** |')
        [IO.File]::WriteAllText($guide, $g, $utf8)
    }
    # Router ports 80/443 (scripts\Set-IRLPortMap.ps1): opened, or closed again, along with the phone's ports.
    if (-not $relayHost -and "$($settings.portMap)" -ne 'Off' -and (Test-Path "$InstallDir\scripts\Set-IRLPortMap.ps1")) {
        try { $pm = & "$InstallDir\scripts\Set-IRLPortMap.ps1" -InstallDir $InstallDir -Quiet; if ($pm.ok) { Ok $pm.message } } catch { }
    }
    # Restart the web server and dashboard with the new settings (IRL Homekit starts them again within seconds).
    Get-Process caddy -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$InstallDir\*" } | Stop-Process -Force
    $dash = (Get-NetTCPConnection -LocalPort 8090 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
    if ($dash) { Stop-Process -Id $dash -Force -ErrorAction SilentlyContinue }
    if ($mode -eq 'off') { Write-Host "`nDone." -ForegroundColor Green; if ($interactive) { Read-Host 'Press Enter to close' }; return }
}
if (-not $settings.domain) { Write-Host "`nRemote access is off. Run this again and choose 1 or 2 to set it up." ; return }

# ------------------------------------------------------------------ 3. check
$d = $settings.domain; $st = $settings.studioDomain
Head 'Checking'
$appRunning = [bool](Get-NetTCPConnection -LocalPort 8090 -State Listen -ErrorAction SilentlyContinue)   # the dashboard runs while the app is open
if (-not $appRunning) {
    Say 'Opening IRL Homekit (the web server runs while it is open)...'
    & schtasks.exe /run /tn 'IRL Homekit' | Out-Null
    Start-Sleep 25
}

# DNS
$dnsOk = $true
foreach ($name in $d, $st) {
    $ip = $null; $deadline = (Get-Date).AddMinutes($(if ($interactive) { 3 } else { 1 }))
    do {
        try { $ip = (Resolve-DnsName $name -Server 1.1.1.1 -Type A -DnsOnly -QuickTimeout -ErrorAction Stop | Where-Object IPAddress | Select-Object -First 1).IPAddress } catch { $ip = $null }
        if ($ip -eq $target) { break }
        Start-Sleep 10
    } while ((Get-Date) -lt $deadline)
    if ($ip -eq $target) { Ok "$name points to $targetName" }
    else {
        $dnsOk = $false
        if (-not $ip) { Bad "$name doesn't exist yet. Add its DNS record (new records can take up to 30 minutes to appear)." }
        else {
            Bad "$name points to $ip, but it should point to $targetName."
            Say "Update its A record to $target. On Cloudflare, set Proxy status to `"DNS only`" (grey cloud)."
        }
    }
}

# Certificate (proves the internet can reach this PC on ports 80/443)
$certDir = "$InstallDir\caddy\data\certificates\acme-v02.api.letsencrypt.org-directory"
$since = Get-Date
$certOk = $true
if ($dnsOk) {
    Say 'Waiting for the free HTTPS certificate (up to 2 minutes)...'
    $deadline = (Get-Date).AddMinutes(2)
    while ((Get-Date) -lt $deadline -and -not ((Test-Path "$certDir\$d\$d.crt") -and (Test-Path "$certDir\$st\$st.crt"))) { Start-Sleep 5 }
}
foreach ($name in $d, $st) {
    if (Test-Path "$certDir\$name\$name.crt") { Ok "HTTPS certificate for $name" ; continue }
    $certOk = $false
    $err = Get-Content "$InstallDir\logs\caddy.log" -Tail 200 -ErrorAction SilentlyContinue | Where-Object { $_ -match '"level":"error"' -and $_ -match [regex]::Escape($name) } | Select-Object -Last 1
    if (-not $dnsOk) { Bad "No certificate for $name yet: fix DNS first, then run this again." }
    elseif ($err -match 'Timeout during connect|Connection refused|connection reset|firewall|Timeout after connect') {
        Bad "Let's Encrypt couldn't reach this PC for $name. $(if ($relayHost) { 'The relay isn''t passing ports 80 and 443 through yet.' } else { 'Your router isn''t forwarding ports 80 and 443 yet.' })"
    } else { Bad "No certificate for $name yet. $(if ($relayHost) { 'Usually the relay VM doesn''t let ports 80 and 443 in yet.' } else { 'Usually the router isn''t forwarding ports 80 and 443.' })" }
}
if (-not $certOk -and $dnsOk -and $relayHost) {
    Say 'On Oracle Cloud: your VM > Subnet > Security list > Add ingress rules for TCP 80 and TCP 443 (source 0.0.0.0/0).'
    Say 'Also check Status (Start menu) shows the relay as connected. Step by step: docs\RELAY.md'
} elseif (-not $certOk -and $dnsOk) {
    $pm = try { Get-Content "$InstallDir\logs\portmap.json" -Raw | ConvertFrom-Json } catch { $null }
    if ($pm -and -not $pm.ok -and $pm.problem -ne 'unsupported') { Say $pm.message }
    Say "On your router, forward TCP 80 and TCP 443 to this PC ($lan). Router steps: docs\ROUTER.md"
    if ($interactive -and $gateway -and (Read-Host "Open your router's page ($gateway) now? (Y/n)") -notmatch '^n') { Start-Process "http://$gateway" }
}

# ------------------------------------------------------------------ 4. result
if ($dnsOk -and $certOk) {
    Write-Host "`nYour remote dashboard works." -ForegroundColor Green
    Write-Host "    Dashboard  https://$d"
    Write-Host "    Studio     https://$st"
    Write-Host '    On your phone: open it with Wi-Fi off once to be sure, sign in, and "Add to Home Screen" for an app icon.'
    Write-Host '    (Some routers can''t open your own address from inside your home Wi-Fi; that''s normal.)'
} else {
    Write-Host "`nAlmost there: fix the items marked FIX above, then run Start menu > IRL Homekit - Set up remote dashboard" -ForegroundColor Yellow
    Write-Host 'and press Enter to check again.'
}
if ($interactive) { Read-Host "`nPress Enter to close" }
