<#
Opens IRL Homekit's ports on your home router by itself (UPnP, or NAT-PMP on routers that use that), so most people
need no port forwarding and no relay server. Nothing to sign up for: the PC asks the router, the way game consoles
and video-call apps do.

It also says plainly when that can't work:
  - the router has it switched off: turn on "UPnP" in the router's settings, or forward the ports by hand
    (docs/ROUTER.md);
  - the router's own internet address is a private one: a second router (the internet provider's modem) sits in
    front of it, or the provider shares one public address between many homes (carrier-grade NAT, common with 5G
    home internet and Starlink). Then the phone can't reach this PC from outside however the ports are set, and the
    relay server is the way (docs/RELAY.md).

The ports are opened for 2 hours at a time and the IRL Homekit app renews them while it runs, so they close by
themselves when it's closed or uninstalled. Ports you forwarded by hand are left alone. The result is saved in
logs\portmap.json, which Status and the dashboard show.

    Set-IRLPortMap.ps1            open / renew the ports
    Set-IRLPortMap.ps1 -Remove    close the ports it opened
No administrator rights needed.
#>
param(
    [string] $InstallDir = (Split-Path $PSScriptRoot -Parent),
    [switch] $Remove,
    [switch] $Quiet,
    [int] $LeaseSeconds = 7200,
    # For testing: the router's UPnP description URL (skips discovery) and the NAT-PMP gateway address.
    [string] $DescriptionUrl = '',
    [string] $Gateway = ''
)
$ErrorActionPreference = 'Stop'
$Description = 'IRL Homekit'
function Info($m) { if (-not $Quiet) { Write-Host "    $m" } }
$settings = Get-Content "$InstallDir\settings.json" -Raw | ConvertFrom-Json
$net = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
$lan = "$($net.IPv4Address.IPAddress | Select-Object -First 1)"
if (-not $Gateway) { $Gateway = "$($net.IPv4DefaultGateway.NextHop | Select-Object -First 1)" }

# What the phone (and, with a domain, the remote dashboard) connects to. With a relay server nothing comes in
# through the router, so any ports opened earlier are closed again.
$ports = @(@{ Proto = 'UDP'; Port = 5000; What = 'bonded phone stream' }, @{ Proto = 'UDP'; Port = 8890; What = 'backup phone stream (SRT)' },
           @{ Proto = 'TCP'; Port = 1935; What = 'backup phone stream (RTMP)' })
if (Test-Path "$InstallDir\caddy\Caddyfile") {
    $ports += @{ Proto = 'TCP'; Port = 443; What = 'remote dashboard (HTTPS)' }, @{ Proto = 'TCP'; Port = 80; What = 'remote dashboard (certificate)' }
}
if ($settings.relayHost -or "$($settings.portMap)" -eq 'Off') { $Remove = $true }

# ------------------------------------------------------------------ UPnP (Internet Gateway Device)
# Ask on the network card that has the internet connection: on PCs with WSL, Hyper-V or a VPN the question would
# otherwise go out on a virtual network where no router listens.
function Find-UpnpRouter {
    $u = New-Object Net.Sockets.UdpClient (New-Object Net.IPEndPoint ([Net.IPAddress]::Parse($lan)), 0)
    try {
        $u.Client.SetSocketOption([Net.Sockets.SocketOptionLevel]::IP, [Net.Sockets.SocketOptionName]::MulticastInterface, [Net.IPAddress]::Parse($lan).GetAddressBytes())
        $u.Client.ReceiveTimeout = 700
        foreach ($st in 'urn:schemas-upnp-org:device:InternetGatewayDevice:1', 'urn:schemas-upnp-org:device:InternetGatewayDevice:2',
                        'urn:schemas-upnp-org:service:WANIPConnection:1', 'urn:schemas-upnp-org:service:WANPPPConnection:1') {
            $m = [Text.Encoding]::ASCII.GetBytes("M-SEARCH * HTTP/1.1`r`nHOST: 239.255.255.250:1900`r`nMAN: `"ssdp:discover`"`r`nMX: 2`r`nST: $st`r`n`r`n")
            [void]$u.Send($m, $m.Length, '239.255.255.250', 1900)
            if ($Gateway) { [void]$u.Send($m, $m.Length, $Gateway, 1900) }   # some routers only answer when asked directly
        }
        $until = (Get-Date).AddSeconds(3); $from = New-Object Net.IPEndPoint ([Net.IPAddress]::Any, 0)
        while ((Get-Date) -lt $until) {
            try { $r = [Text.Encoding]::ASCII.GetString($u.Receive([ref]$from)) } catch { continue }
            if ($r -match '(?im)^LOCATION:\s*(\S+)') { return $Matches[1] }
        }
    } finally { $u.Close() }
    ''
}
function Open-Upnp($url) {
    $wc = New-Object Net.WebClient; $wc.Proxy = $null
    $x = [xml]$wc.DownloadString($url)
    $svc = @($x.SelectNodes('//*[local-name()="service"]') | Where-Object { "$($_.serviceType)" -match 'WAN(IP|PPP)Connection:\d' }) |
        Sort-Object { if ("$($_.serviceType)" -match 'WANIP') { 0 } else { 1 } } | Select-Object -First 1
    if (-not $svc) { return $null }
    $base = $x.SelectSingleNode('//*[local-name()="URLBase"]')
    $root = if ($base -and "$($base.InnerText)".Trim()) { "$($base.InnerText)".Trim() } else { $url }
    $dev = $x.SelectSingleNode('//*[local-name()="device"]')
    [pscustomobject]@{ Type = "$($svc.serviceType)"; Control = (New-Object Uri ((New-Object Uri $root), "$($svc.controlURL)".Trim())).AbsoluteUri
        Name = ("$($dev.manufacturer) $($dev.modelName)".Trim() -replace '\s+', ' ') }
}
# One SOAP call. Returns the answer's fields, or Error = the router's UPnP error code (718 = port taken, ...).
function Invoke-Upnp($r, $action, $fields) {
    $inner = ($fields.GetEnumerator() | ForEach-Object { "<$($_.Key)>$([Security.SecurityElement]::Escape("$($_.Value)"))</$($_.Key)>" }) -join ''
    $body = "<?xml version=`"1.0`"?><s:Envelope xmlns:s=`"http://schemas.xmlsoap.org/soap/envelope/`" s:encodingStyle=`"http://schemas.xmlsoap.org/soap/encoding/`"><s:Body><u:$action xmlns:u=`"$($r.Type)`">$inner</u:$action></s:Body></s:Envelope>"
    $req = [Net.HttpWebRequest]::Create($r.Control); $req.Method = 'POST'; $req.Proxy = $null; $req.Timeout = 6000
    $req.ContentType = 'text/xml; charset="utf-8"'; $req.Headers.Add('SOAPAction', "`"$($r.Type)#$action`"")
    $b = [Text.Encoding]::UTF8.GetBytes($body); $req.ContentLength = $b.Length
    $st = $req.GetRequestStream(); $st.Write($b, 0, $b.Length); $st.Close()
    try { $resp = $req.GetResponse() } catch [Net.WebException] { $resp = $_.Exception.Response; if (-not $resp) { return @{ Error = 'no answer' } } }
    try { $text = (New-Object IO.StreamReader $resp.GetResponseStream()).ReadToEnd() } finally { $resp.Close() }
    $out = @{ Error = '' }
    try { $x = [xml]$text } catch { return @{ Error = "unreadable answer (HTTP $([int]$resp.StatusCode))" } }
    $code = $x.SelectSingleNode('//*[local-name()="errorCode"]')
    if ($code) { $out.Error = "$($code.InnerText)".Trim(); return $out }
    $node = $x.SelectSingleNode("//*[local-name()='$($action)Response']")
    if ($node) { foreach ($c in $node.ChildNodes) { $out[$c.LocalName] = "$($c.InnerText)" } }
    $out
}
function Get-UpnpEntry($r, $p) {
    Invoke-Upnp $r 'GetSpecificPortMappingEntry' ([ordered]@{ NewRemoteHost = ''; NewExternalPort = $p.Port; NewProtocol = $p.Proto })
}
function Set-UpnpPort($r, $p) {
    $f = [ordered]@{ NewRemoteHost = ''; NewExternalPort = $p.Port; NewProtocol = $p.Proto; NewInternalPort = $p.Port; NewInternalClient = $lan
        NewEnabled = 1; NewPortMappingDescription = $Description; NewLeaseDuration = $LeaseSeconds }
    $a = Invoke-Upnp $r 'AddPortMapping' $f
    if ($a.Error -eq '725') { $f.NewLeaseDuration = 0; $a = Invoke-Upnp $r 'AddPortMapping' $f }   # router only takes permanent ones
    if (-not $a.Error) { return @{ Ok = $true; Note = 'opened' } }
    # Taken: fine if it already points at this PC (you forwarded it by hand), else another device has it.
    $e = Get-UpnpEntry $r $p
    if (-not $e.Error -and $e.NewInternalClient -eq $lan -and "$($e.NewInternalPort)" -eq "$($p.Port)") { return @{ Ok = $true; Note = 'already forwarded to this PC' } }
    if (-not $e.Error -and $e.NewInternalClient) { return @{ Ok = $false; Note = "already forwarded to another device ($($e.NewInternalClient))" } }
    $why = switch ($a.Error) { '718' { 'already set up in the router''s own port forwarding (fine if that points at this PC)' } { $_ -in '606', '401', '501' } { 'the router refused (it may only allow this for some devices)' }
        '724' { 'the router needs the same inside and outside port' } default { "the router refused (error $($a.Error))" } }
    @{ Ok = $false; Note = $why }
}
function Remove-UpnpPort($r, $p) {
    $e = Get-UpnpEntry $r $p   # only ours: a forward you made by hand stays
    if ($e.Error -or $e.NewPortMappingDescription -ne $Description -or $e.NewInternalClient -ne $lan) { return $false }
    if (-not (Invoke-Upnp $r 'DeletePortMapping' ([ordered]@{ NewRemoteHost = ''; NewExternalPort = $p.Port; NewProtocol = $p.Proto })).Error) { return $true }
    # Some routers (Verizon's, for one) answer DeletePortMapping with "invalid args" but do the IGD v2 range delete,
    # which only ever removes this PC's own entries (NewManage 0).
    if ($r.Type -notmatch ':2$') { return $false }
    -not (Invoke-Upnp $r 'DeletePortMappingRange' ([ordered]@{ NewStartPort = $p.Port; NewEndPort = $p.Port; NewProtocol = $p.Proto; NewManage = 0 })).Error
}

# ------------------------------------------------------------------ NAT-PMP (RFC 6886; Apple and some other routers)
function Send-NatPmp([byte[]] $msg, [int] $len) {
    $u = New-Object Net.Sockets.UdpClient (New-Object Net.IPEndPoint ([Net.IPAddress]::Parse($lan)), 0)
    try {
        $u.Client.ReceiveTimeout = 500
        foreach ($try in 1..3) {
            [void]$u.Send($msg, $msg.Length, $Gateway, 5351)
            $from = New-Object Net.IPEndPoint ([Net.IPAddress]::Any, 0)
            try { $r = $u.Receive([ref]$from); if ($r.Length -ge $len -and $r[1] -eq ($msg[1] + 128)) { return , $r } } catch { }
        }
    } finally { $u.Close() }
    $null
}
function BE16($b, $i) { ([int]$b[$i] -shl 8) -bor $b[$i + 1] }
function Get-NatPmpIp {
    $r = Send-NatPmp ([byte[]](0, 0)) 12
    if (-not $r -or (BE16 $r 2) -ne 0) { return '' }
    "$($r[8]).$($r[9]).$($r[10]).$($r[11])"
}
function Set-NatPmpPort($p, [int] $life) {
    $op = if ($p.Proto -eq 'UDP') { 1 } else { 2 }
    $ext = if ($life) { $p.Port } else { 0 }
    $m = [byte[]](0, $op, 0, 0, ($p.Port -shr 8), ($p.Port -band 255), ($ext -shr 8), ($ext -band 255),
                  (($life -shr 24) -band 255), (($life -shr 16) -band 255), (($life -shr 8) -band 255), ($life -band 255))
    $r = Send-NatPmp $m 16
    if (-not $r) { return @{ Ok = $false; Note = 'no answer from the router' } }
    $rc = BE16 $r 2
    if ($rc -ne 0) { return @{ Ok = $false; Note = $(switch ($rc) { 2 { 'the router has it switched off' } 3 { 'the router is out of ports' } default { "the router refused (code $rc)" } }) } }
    if ($life -and (BE16 $r 10) -ne $p.Port) { [void](Set-NatPmpPort $p 0); return @{ Ok = $false; Note = "the router offered port $(BE16 $r 10) instead (taken)" } }
    @{ Ok = $true; Note = 'opened' }
}

# ------------------------------------------------------------------ run
$state = [ordered]@{ time = (Get-Date -Format o); method = ''; router = ''; lanIp = $lan; externalIp = ''; problem = ''; ok = $false; ports = @(); message = '' }
$router = $null
if ($lan) {
    $loc = if ($DescriptionUrl) { $DescriptionUrl } else { Find-UpnpRouter }
    if ($loc) { try { $router = Open-Upnp $loc } catch { $router = $null } }
}
if ($router) {
    $state.method = 'UPnP'; $state.router = $router.Name
    $state.externalIp = (Invoke-Upnp $router 'GetExternalIPAddress' @{}).NewExternalIPAddress
} elseif ($lan -and $Gateway) {
    $ip = Get-NatPmpIp
    if ($ip) { $state.method = 'NAT-PMP'; $state.externalIp = $ip }
}

if ($Remove) {
    $closed = 0
    if ($state.method -eq 'UPnP') { foreach ($p in $ports + @(@{ Proto = 'TCP'; Port = 443 }, @{ Proto = 'TCP'; Port = 80 })) { if (Remove-UpnpPort $router $p) { $closed++ } } }
    elseif ($state.method -eq 'NAT-PMP') { foreach ($p in $ports) { if ((Set-NatPmpPort $p 0).Ok) { $closed++ } } }
    $state.message = if ($closed) { "closed the $closed router port(s) IRL Homekit had opened" } else { 'no router ports to close' }
    Info $state.message
    Remove-Item "$InstallDir\logs\portmap.json" -ErrorAction SilentlyContinue
    return [pscustomobject]$state
}

if (-not $state.method) {
    $state.problem = 'unsupported'
    $state.message = "Your router didn't answer the request to open ports automatically. Turn on UPnP in the router's settings (often under Advanced, NAT or Gaming) and open IRL Homekit again, or forward the ports by hand (docs\ROUTER.md). If you already forwarded them, you're all set."
} else {
    foreach ($p in $ports) {
        $r = if ($state.method -eq 'UPnP') { Set-UpnpPort $router $p } else { Set-NatPmpPort $p $LeaseSeconds }
        $state.ports += [ordered]@{ proto = $p.Proto; port = $p.Port; what = $p.What; ok = $r.Ok; note = $r.Note }
    }
    $failed = @($state.ports | Where-Object { -not $_.ok })
    $ext = "$($state.externalIp)"
    # The router's own internet address says whether anything outside can reach it.
    if ($ext -match '^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.') {
        $state.problem = 'cgnat'
        $state.message = "Your internet provider shares one public address between many customers (carrier-grade NAT, your router's internet address is $ext), so your phone can't reach this PC from outside, even with the ports open. Use the free relay server instead (docs\RELAY.md)."
    } elseif ($ext -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)') {
        $state.problem = 'double-nat'
        $state.message = "Your router's internet address is $ext, a private one: there's another router in front of it (usually the internet provider's modem), or the provider uses carrier-grade NAT. Open the same ports on that modem too, or set it to bridge mode; if that's not possible, use the relay server (docs\RELAY.md)."
    } elseif ($failed) {
        $state.problem = 'refused'
        $state.message = "The router opened $($state.ports.Count - $failed.Count) of $($state.ports.Count) ports. Not opened: " + (($failed | ForEach-Object { "$($_.proto) $($_.port) ($($_.note))" }) -join '; ') + '. Forward those to this PC by hand (docs\ROUTER.md); a port another device already has must be freed on the router first.'
    } else {
        $state.ok = $true
        $state.message = "Router ports opened automatically ($($state.method)$(if ($state.router) { ", $($state.router)" })): no port forwarding needed."
    }
}
New-Item -ItemType Directory -Force "$InstallDir\logs" | Out-Null
# The app's log (logs\watchdog.log) gets a line when the answer changes, not every renewal.
$before = try { (Get-Content "$InstallDir\logs\portmap.json" -Raw | ConvertFrom-Json).message } catch { '' }
if ($before -ne $state.message) { Add-Content "$InstallDir\logs\watchdog.log" ('{0}  router ports: {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $state.message) -ErrorAction SilentlyContinue }
[IO.File]::WriteAllText("$InstallDir\logs\portmap.json", ($state | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
if ($state.ok) { Info $state.message } elseif (-not $Quiet) { Write-Warning $state.message }
[pscustomobject]$state
