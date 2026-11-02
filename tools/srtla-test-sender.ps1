# Minimal single-link SRTLA sender for testing go-irl: ffmpeg (SRT caller) -> 127.0.0.1:$LocalPort -> SRTLA -> go-irl.
# Implements the SRTLA registration (REG1 -> REG2 -> REG2 -> REG3) then relays SRT packets both ways.
param([int]$LocalPort = 6000, [string]$GoIrlHost = '127.0.0.1', [int]$GoIrlPort = 5000, [int]$Seconds = 75)
$ErrorActionPreference = 'Stop'
$REG1 = 0x9200; $REG2 = 0x9201; $REG3 = 0x9202
function Get-PktType([byte[]]$b) { if ($b.Length -lt 2) { return -1 }; (([int]$b[0]) -shl 8) -bor [int]$b[1] }
function Pkt([int]$type, [byte[]]$id) { $p = New-Object byte[] (2 + $id.Length); $p[0] = [byte]($type -shr 8); $p[1] = [byte]($type -band 0xFF); [Array]::Copy($id, 0, $p, 2, $id.Length); , $p }

$remote = New-Object System.Net.Sockets.UdpClient
$remote.Connect($GoIrlHost, $GoIrlPort)
$remote.Client.ReceiveTimeout = 3000
$any = New-Object System.Net.IPEndPoint ([Net.IPAddress]::Any, 0)

$id = New-Object byte[] 256
$half = New-Object byte[] 128; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($half); [Array]::Copy($half, $id, 128)
$p = Pkt $REG1 $id; [void]$remote.Send($p, $p.Length)
$r = $remote.Receive([ref]$any)
if ((Get-PktType $r) -ne $REG2 -or $r.Length -ne 258) { throw ("expected REG2, got type 0x{0:X4} len {1}" -f (Get-PktType $r), $r.Length) }
$full = $r[2..257]
"REG2 received (group id assigned)"
$p = Pkt $REG2 $full; [void]$remote.Send($p, $p.Length)
$r = $remote.Receive([ref]$any)
if ((Get-PktType $r) -ne $REG3) { throw ("expected REG3, got type 0x{0:X4}" -f (Get-PktType $r)) }
"REG3 received - connection registered, relaying"

$local = New-Object System.Net.Sockets.UdpClient (New-Object System.Net.IPEndPoint ([Net.IPAddress]::Loopback, $LocalPort))
$ffmpegEp = $null; $up = 0; $down = 0; $srtla = 0
$deadline = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $deadline) {
    $idle = $true
    while ($local.Available -gt 0) {
        $ep = New-Object System.Net.IPEndPoint ([Net.IPAddress]::Any, 0)
        $b = $local.Receive([ref]$ep); $ffmpegEp = $ep
        [void]$remote.Send($b, $b.Length); $up++; $idle = $false
    }
    while ($remote.Available -gt 0) {
        $b = $remote.Receive([ref]$any); $t = Get-PktType $b
        if ($t -ge 0x9000 -and $t -le 0x92FF) { $srtla++ }                         # SRTLA ack/keepalive: not for ffmpeg
        elseif ($ffmpegEp) { [void]$local.Send($b, $b.Length, $ffmpegEp); $down++ }
        $idle = $false
    }
    if ($idle) { Start-Sleep -Milliseconds 1 }
}
"relayed up=$up down=$down srtla-control=$srtla"
$local.Close(); $remote.Close()
