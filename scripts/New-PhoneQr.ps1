# Makes the "Connect your phone" QR code as a picture, for Setup.exe's last page: waits for IRL Homekit's dashboard
# and for its HTTPS certificate (so the phone doesn't get a certificate warning), then asks the dashboard for a
# one-time sign-in link (it works once, for 10 minutes) and draws it with tools\qr-bmp.mjs.
#   New-PhoneQr.ps1 -OutFile qr.bmp
# Writes <OutFile>.txt with one line: "ok" or "nodomain" / "nodashboard" / "otherdevice" (the router sends 443/80
# to another device) / "unreachable" (nothing on the internet reaches this PC) / "nocert" / "error <reason>".
param(
    [string] $InstallDir = (Split-Path $PSScriptRoot -Parent),
    [Parameter(Mandatory)] [string] $OutFile,
    [int] $WaitSeconds = 120
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
function Done($status) { [IO.File]::WriteAllText("$OutFile.txt", $status); Write-Output $status; exit 0 }
Remove-Item -LiteralPath $OutFile, "$OutFile.txt" -Force -ErrorAction SilentlyContinue
try {
    $settings = Get-Content "$InstallDir\settings.json" -Raw | ConvertFrom-Json
    $domain = "$($settings.domain)".Trim()
    if (-not $domain) { Done 'nodomain' }
    $port = try { (Get-Content "$InstallDir\dashboard\config.json" -Raw | ConvertFrom-Json).port } catch { $null }
    if (-not $port) { $port = 8090 }
    $until = (Get-Date).AddSeconds($WaitSeconds)
    while (-not (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) -and (Get-Date) -lt $until) { Start-Sleep -Seconds 2 }
    if (-not (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)) { Done 'nodashboard' }
    # The web server gets its certificate within a minute of starting, if the internet can reach this PC.
    $cert = "$InstallDir\caddy\data\certificates\acme-v02.api.letsencrypt.org-directory\$domain\$domain.crt"
    while (-not (Test-Path $cert) -and (Get-Date) -lt $until) { Start-Sleep -Seconds 3 }
    if (-not (Test-Path $cert)) {
        # Why not, from Let's Encrypt's answer in the web server's log: another device answered on this home's address
        # (the router forwards 443/80 to another PC, maybe one with IRL Homekit), or nothing answered at all.
        $err = Get-Content "$InstallDir\logs\caddy.log" -Tail 400 -ErrorAction SilentlyContinue | Where-Object { $_ -match '"level":"error"' -and $_ -match [regex]::Escape($domain) } | Select-Object -Last 1
        if ($err -match 'Incorrect validation certificate|Cannot negotiate ALPN|tls: internal error|Error getting validation data|Invalid response from') { Done 'otherdevice' }
        if ($err -match 'Timeout during connect|Connection refused|connection reset|Timeout after connect|Fetching http') { Done 'unreachable' }
        Done 'nocert'
    }
    $link = (Invoke-RestMethod "http://127.0.0.1:$port/pair/new" -Method Post -Headers @{ 'X-IRLHK' = '1' } -TimeoutSec 10).url
    if (-not $link) { Done 'error the dashboard gave no link' }
    $node = @("$InstallDir\node\node.exe", (Get-Command node.exe -ErrorAction SilentlyContinue).Source) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $node) { Done 'error Node.js not found' }
    & $node "$InstallDir\tools\qr-bmp.mjs" $link $OutFile 6 | Out-Null
    if (-not (Test-Path $OutFile)) { Done 'error the picture was not made' }
    Done 'ok'
} catch { Done "error $($_.Exception.Message)" }
