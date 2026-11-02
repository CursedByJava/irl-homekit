# Keeps the NOALBS Twitch chat token alive. Run hourly by the watchdog.
# Twitch chat tokens expire after a few hours; NOALBS cannot refresh them itself, so this does it through the
# TwitchTokenGenerator refresh API with the refresh token saved by Set-TwitchBotToken.ps1, then restarts NOALBS.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$secretsFile = "$root\secrets.json"
$s = Get-Content $secretsFile -Raw | ConvertFrom-Json
if (-not $s.twitchBotToken -or -not $s.twitchBotRefresh) { exit 0 }   # chat commands not set up

function Log($msg) { Add-Content "$root\logs\watchdog.log" ('{0}  twitch token: {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) }

# Twitch reports expires_in = 0 for tokens that never expire; only refresh when the token is rejected or close to expiring.
try {
    $v = Invoke-RestMethod 'https://id.twitch.tv/oauth2/validate' -Headers @{ Authorization = "OAuth $($s.twitchBotToken)" } -TimeoutSec 15
    if ([int]$v.expires_in -eq 0 -or [int]$v.expires_in -gt 7200) { exit 0 }
} catch {
    # A network error is not a rejected token; only a 401 means it must be replaced.
    if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -ne 401) { exit 0 }
    if (-not $_.Exception.Response) { exit 0 }
}

try {
    $r = Invoke-RestMethod "https://twitchtokengenerator.com/api/refresh/$($s.twitchBotRefresh)" -TimeoutSec 30
} catch { Log "refresh request failed: $($_.Exception.Message)"; exit 1 }
$token = if ($r.token) { $r.token } else { $r.access_token }
$refresh = if ($r.refresh) { $r.refresh } else { $r.refresh_token }
if (-not $token) { Log "refresh failed: $($r | ConvertTo-Json -Compress)"; exit 1 }

$s | Add-Member -Force twitchBotToken $token
if ($refresh) { $s | Add-Member -Force twitchBotRefresh $refresh }
$s | ConvertTo-Json | Set-Content -Encoding UTF8 $secretsFile
[IO.File]::WriteAllText("$root\noalbs\.env", "TWITCH_BOT_USERNAME=$($s.twitchBotUser)`nTWITCH_BOT_OAUTH=oauth:$token`nLOG_DIR=$root\logs`n", (New-Object Text.UTF8Encoding $false))
Get-Process -Name noalbs -ErrorAction SilentlyContinue | Stop-Process -Force   # watchdog restarts it with the new token
Log 'refreshed, NOALBS restarted'
