# Writes the web server's settings (caddy\Caddyfile) for the dashboard address in settings.json, or removes them
# when the dashboard is on this PC only. Used by the installer, Setup-RemoteDashboard.ps1 and the app itself.
#   A name (DuckDNS or your own domain): https://name and https://studio.name, certificates from Let's Encrypt.
#   No account (settings.json "dashboardOnIp"): https://<your internet address>, with Let's Encrypt's certificates
#   for IP addresses (short-lived, renewed by themselves); Studio is at /studio.
#   -Reload   apply it to the running web server now
param([string] $InstallDir = (Split-Path $PSScriptRoot -Parent), [switch] $Reload)
$ErrorActionPreference = 'Stop'
$settings = Get-Content "$InstallDir\settings.json" -Raw | ConvertFrom-Json
$file = "$InstallDir\caddy\Caddyfile"
$domain = "$($settings.domain)".Trim()
if (-not $domain) { if (Test-Path $file) { Remove-Item -LiteralPath $file -Force }; return }

$ip = [bool]$settings.dashboardOnIp
$tpl = [IO.File]::ReadAllText($(if (Test-Path "$InstallDir\templates\Caddyfile") { "$InstallDir\templates\Caddyfile" } else { "$PSScriptRoot\..\templates\Caddyfile" }))
# Behind the relay, dashboard visitors arrive from the relay's tunnel address (10.66.66.1), with their own address in
# a PROXY header added by the relay (sign-in limits are per visitor).
$servers = if ($settings.relayHost) { "servers {`n`t`tlistener_wrappers {`n`t`t`tproxy_protocol {`n`t`t`t`ttimeout 5s`n`t`t`t`tallow 10.66.66.1/32`n`t`t`t}`n`t`t`ttls`n`t`t}`n`t}" } else { '' }
$names = if ($ip -or -not $settings.studioDomain) { $domain } else { "$domain, $($settings.studioDomain)" }
# A browser opening an address by its number sends no name, so tell the web server which certificate that means.
$global = if ($ip) { "default_sni $domain" } else { '' }
$tls = if ($ip) { "tls {`n`t`tissuer acme {`n`t`t`tprofile shortlived`n`t`t}`n`t}" } else { '' }
$text = $tpl.Replace('{{INSTALL_DIR}}', ($InstallDir -replace '\\', '/')).Replace('{{DOMAIN}}', $names).Replace('{{SERVERS}}', $servers).Replace('{{GLOBAL}}', $global).Replace('{{TLS}}', $tls)
New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null
# Sites of your own (a second PC's dashboard, anything else) go in caddy\extra.caddy: this file is written again
# whenever your settings change, so anything added to it directly would be lost. That one is added as it is.
$extra = "$InstallDir\caddy\extra.caddy"
if (Test-Path $extra) { $text = $text + "`n" + [IO.File]::ReadAllText($extra).TrimEnd() + "`n" }
[IO.File]::WriteAllText($file, $text, (New-Object Text.UTF8Encoding $false))

if ($Reload -and (Get-NetTCPConnection -LocalPort 2019 -State Listen -ErrorAction SilentlyContinue)) {
    & "$InstallDir\caddy\caddy.exe" reload --config $file --adapter caddyfile --address 127.0.0.1:2019 2>&1 | Out-Null
}
