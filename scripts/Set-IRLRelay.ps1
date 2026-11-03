<#
Connects this PC to your relay server (docs/RELAY.md) so the router needs no port forwarding.

The PC dials out to the relay over WireGuard: the official WireGuard for Windows (signed by WireGuard LLC, so Smart
App Control and antivirus allow it), installed here if it's missing, checksum-verified. The tunnel runs as a Windows
service that starts at boot, and only carries traffic for the relay's tunnel address (10.66.66.1): the rest of the
PC's internet is untouched.

Both ends work out the tunnel keys from the relay password in secrets.json (relayToken), the same password that's in
the VM's setup script (relay\relay-vps.sh), so nothing else needs copying between them.

    Set-IRLRelay.ps1                 set up / refresh the tunnel for settings.json "relayHost"
    Set-IRLRelay.ps1 -WaitSeconds 60 ...and wait up to a minute for the relay to answer
    Set-IRLRelay.ps1 -Off            remove the tunnel (WireGuard itself stays installed)
Needs administrator rights (the installer and the IRL Homekit app have them).
#>
param(
    [string] $InstallDir = (Split-Path $PSScriptRoot -Parent),
    [switch] $Off,
    [int] $WaitSeconds = 0
)
$ErrorActionPreference = 'Stop'
$Tunnel = 'irlhk'
$Service = "WireGuardTunnel`$$Tunnel"
$WgDir = "$env:ProgramFiles\WireGuard"
# Pinned. Bump both together; the download is refused unless the checksum matches and WireGuard LLC signed it.
$WgMsi = @{ Url = 'https://download.wireguard.com/windows-client/wireguard-amd64-1.1.1.msi'
            Sha = '7bfed60ad61b785c914b38b61555a975488e1d3ec472dbfb2fcdf498fca75242' }
$VmIp = '10.66.66.1'; $PcIp = '10.66.66.2'; $WgPort = 51820
$conf = "$InstallDir\relay\$Tunnel.conf"

function Info($m) { Write-Host "    $m" }
# WireGuard removes the service in the background; wait for it, or installing it again fails.
function Remove-Tunnel {
    & "$WgDir\wireguard.exe" /uninstalltunnelservice $Tunnel
    for ($i = 0; $i -lt 40 -and (Get-Service $Service -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 }
}
$settings = Get-Content "$InstallDir\settings.json" -Raw | ConvertFrom-Json
$secrets = Get-Content "$InstallDir\secrets.json" -Raw | ConvertFrom-Json
$relayHost = if ($Off) { '' } else { "$($settings.relayHost)" }

if (-not $relayHost) {
    if (Get-Service $Service -ErrorAction SilentlyContinue) {
        Remove-Tunnel
        Info 'relay tunnel removed (WireGuard itself stays installed: remove it in Settings > Apps if you don''t use it)'
    }
    Remove-Item $conf -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Connected = $null; Message = 'no relay' }
}
if ($secrets.relayToken -notmatch '^[A-Za-z0-9]{24,64}$') { throw 'secrets.json has no relay password (relayToken). Run Setup again.' }

# 1. WireGuard for Windows.
if (-not (Test-Path "$WgDir\wireguard.exe")) {
    $msi = Join-Path "$InstallDir\_downloads" (Split-Path $WgMsi.Url -Leaf)
    New-Item -ItemType Directory -Force (Split-Path $msi) | Out-Null
    if (-not (Test-Path $msi) -or (Get-FileHash $msi).Hash.ToLower() -ne $WgMsi.Sha) {
        Info 'downloading WireGuard'
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest $WgMsi.Url -OutFile $msi -UseBasicParsing
    }
    if ((Get-FileHash $msi).Hash.ToLower() -ne $WgMsi.Sha) { Remove-Item $msi -Force; throw 'WireGuard download: checksum mismatch, refused.' }
    $sig = Get-AuthenticodeSignature $msi
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'CN=WireGuard LLC') { throw 'WireGuard download: not signed by WireGuard LLC, refused.' }
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart DO_NOT_LAUNCH=1" -Wait -PassThru
    if ($p.ExitCode -notin 0, 3010) { throw "WireGuard didn't install (Windows Installer error $($p.ExitCode))." }
    Info 'WireGuard installed'
}

# 2. Keys: SHA-256 of a label and the relay password (the VM's setup script does exactly the same).
function Get-Key($label) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $k = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("${label}:$($secrets.relayToken)"))
    $k[0] = $k[0] -band 248; $k[31] = ($k[31] -band 127) -bor 64   # a proper X25519 private key ("wg genkey" form)
    [Convert]::ToBase64String($k)
}
# A WireGuard public key is X25519(private key, 9) (RFC 7748). Worked out here rather than with "wg pubkey", which
# refuses keys piped in from some PowerShell hosts.
function Get-PublicKey([string]$private) {
    Add-Type -AssemblyName System.Numerics
    $p = [Numerics.BigInteger]::Pow(2, 255) - 19
    function Fe($v) { $r = [Numerics.BigInteger]::Remainder($v, $p); if ($r.Sign -lt 0) { $r + $p } else { $r } }
    $k = [Convert]::FromBase64String($private); $k[0] = $k[0] -band 248; $k[31] = ($k[31] -band 127) -bor 64
    $n = [Numerics.BigInteger]::new([byte[]]($k + [byte]0))
    $x1 = [Numerics.BigInteger]9; $x2 = [Numerics.BigInteger]::One; $z2 = [Numerics.BigInteger]::Zero; $x3 = $x1; $z3 = [Numerics.BigInteger]::One
    for ($t = 254; $t -ge 0; $t--) {
        if (-not ([Numerics.BigInteger]::op_RightShift($n, $t)).IsEven) { $x2, $x3 = $x3, $x2; $z2, $z3 = $z3, $z2; $sw = $true } else { $sw = $false }
        $a = Fe ($x2 + $z2); $aa = Fe ($a * $a); $b = Fe ($x2 - $z2); $bb = Fe ($b * $b); $e = Fe ($aa - $bb)
        $c = Fe ($x3 + $z3); $d = Fe ($x3 - $z3); $da = Fe ($d * $a); $cb = Fe ($c * $b)
        $x3 = Fe (($da + $cb) * ($da + $cb)); $z3 = Fe ($x1 * (Fe (($da - $cb) * ($da - $cb))))
        $x2 = Fe ($aa * $bb); $z2 = Fe ($e * (Fe ($aa + 121665 * $e)))
        if ($sw) { $x2, $x3 = $x3, $x2; $z2, $z3 = $z3, $z2 }
    }
    $u = Fe ($x2 * [Numerics.BigInteger]::ModPow($z2, $p - 2, $p))
    $bytes = New-Object byte[] 32; $raw = $u.ToByteArray(); [Array]::Copy($raw, $bytes, [Math]::Min(32, $raw.Length))
    [Convert]::ToBase64String($bytes)
}
$vmPub = Get-PublicKey (Get-Key 'irlhk-relay-vm')

# 3. The tunnel config (secrets.json is next to it, so it gets the same protection) and its service.
$text = @"
# IRL Homekit relay tunnel (docs/RELAY.md). Written by IRL Homekit; run Setup again to change it.
[Interface]
PrivateKey = $(Get-Key 'irlhk-relay-pc')
Address = $PcIp/32

[Peer]
# The relay server
PublicKey = $vmPub
Endpoint = ${relayHost}:$WgPort
AllowedIPs = $VmIp/32
PersistentKeepalive = 25
"@
New-Item -ItemType Directory -Force (Split-Path $conf) | Out-Null
$old = if (Test-Path $conf) { [IO.File]::ReadAllText($conf) } else { '' }
$svc = Get-Service $Service -ErrorAction SilentlyContinue
if ($old -ne $text -or -not $svc) {
    if ($svc) { Remove-Tunnel }
    [IO.File]::WriteAllText($conf, $text, (New-Object Text.UTF8Encoding $false))
    & "$WgDir\wireguard.exe" /installtunnelservice $conf
    for ($i = 0; $i -lt 20 -and -not (Get-Service $Service -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 }
    Info "relay tunnel to $relayHost set up (starts with Windows)"
} elseif ($svc.Status -ne 'Running') {
    Start-Service $Service
}

# 4. Connected = the relay answers inside the tunnel.
function Test-Relay { [bool](Test-Connection $VmIp -Count 1 -Quiet -ErrorAction SilentlyContinue) }
$ok = Test-Relay
$deadline = (Get-Date).AddSeconds($WaitSeconds)
while (-not $ok -and (Get-Date) -lt $deadline) { Start-Sleep 3; $ok = Test-Relay }
$msg = if ($ok) { "connected to the relay ($relayHost)" }
       else { "Couldn't reach the relay at $relayHost yet. Check the VM is running, its setup script finished, and its security list lets UDP $WgPort in (docs\RELAY.md)." }
[pscustomobject]@{ Connected = $ok; Message = $msg }
