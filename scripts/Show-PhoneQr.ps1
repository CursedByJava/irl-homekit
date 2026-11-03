# Opens "Connect your phone" in your browser: a QR code to scan with the phone's camera. The phone opens your
# dashboard already signed in, with Open in IRL Pro ready. Start menu > "IRL Homekit - Connect my phone", and the
# end of Setup. Waits (up to a minute) for IRL Homekit's dashboard if it's still starting.
param([string] $InstallDir = (Split-Path $PSScriptRoot -Parent))
$port = try { (Get-Content "$InstallDir\dashboard\config.json" -Raw | ConvertFrom-Json).port } catch { $null }
if (-not $port) { $port = 8090 }
$until = (Get-Date).AddSeconds(60)
while (-not (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) -and (Get-Date) -lt $until) { Start-Sleep -Seconds 2 }
if (-not (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)) {
    Add-Type -AssemblyName System.Windows.Forms
    [void][Windows.Forms.MessageBox]::Show('IRL Homekit isn''t running yet. Open it (the IRL Homekit icon on the desktop), then try again.', 'IRL Homekit')
    exit 1
}
# Right after installing, the web server may still be getting its HTTPS certificate: wait for it (up to 2 minutes),
# so the phone doesn't get a certificate warning.
$domain = try { "$((Get-Content "$InstallDir\settings.json" -Raw | ConvertFrom-Json).domain)".Trim() } catch { '' }
if ($domain) {
    $cert = "$InstallDir\caddy\data\certificates\acme-v02.api.letsencrypt.org-directory\$domain\$domain.crt"
    $until = (Get-Date).AddSeconds(120)
    while (-not (Test-Path $cert) -and (Get-Date) -lt $until) { Start-Sleep -Seconds 3 }
}
# Through Explorer: the browser opens as you, even when this runs from the installer (as administrator).
Start-Process explorer.exe "http://localhost:$port/pair"
