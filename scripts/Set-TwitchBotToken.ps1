# Turns on NOALBS Twitch chat commands (!bitrate, !start, !stop, !switch, !fix ...).
# 1. Go to https://twitchtokengenerator.com, enable only chat:read + chat:edit, click Generate Token and authorize
#    with the account that should reply in chat (your own account is fine).
# 2. Run:  powershell -ExecutionPolicy Bypass -File C:\IRLHomekit\scripts\Set-TwitchBotToken.ps1 -BotUsername <login> -Token <access token> -RefreshToken <refresh token>
# The watchdog then refreshes the token automatically (scripts\Refresh-TwitchToken.ps1).
#    Or just open Start menu > "IRL Homekit - Twitch chat token" and paste when asked.
param([string] $BotUsername, [string] $Token, [string] $RefreshToken)
$ErrorActionPreference = 'Stop'
$settingsFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'settings.json'
$channel = (Get-Content $settingsFile -Raw | ConvertFrom-Json).twitchChannel
# Twitch was skipped in Setup: ask for the channel now and remember it.
if (-not $channel) {
    $channel = ((Read-Host 'Your Twitch channel name') -replace '^(https?://)?(www\.)?twitch\.tv/', '' -replace '[/?].*$', '').Trim().ToLower()
    if (-not $channel) { throw 'A Twitch channel name is needed for chat commands.' }
    $set = Get-Content $settingsFile -Raw | ConvertFrom-Json; $set | Add-Member -Force twitchChannel $channel
    [IO.File]::WriteAllText($settingsFile, ($set | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
}
if (-not $BotUsername) { $BotUsername = Read-Host "Twitch login the bot posts as (press Enter for $channel)"; if (-not $BotUsername) { $BotUsername = $channel } }
if (-not $Token) { $Token = (Read-Host 'Paste the ACCESS TOKEN from twitchtokengenerator.com').Trim() }
if (-not $RefreshToken) { $RefreshToken = (Read-Host 'Paste the REFRESH TOKEN from twitchtokengenerator.com').Trim() }
if ($Token.Length -lt 20 -or $RefreshToken.Length -lt 20) { throw 'Those values look too short. Copy the full Access token and Refresh token and run this again.' }
$root = Split-Path $PSScriptRoot -Parent
$dir = "$root\noalbs"
$Token = $Token -replace '^oauth:', ''
$utf8 = New-Object Text.UTF8Encoding $false

$s = Get-Content "$root\secrets.json" -Raw | ConvertFrom-Json
$s | Add-Member -Force twitchBotUser $BotUsername.ToLower()
$s | Add-Member -Force twitchBotToken $Token
$s | Add-Member -Force twitchBotRefresh $RefreshToken
$s | ConvertTo-Json | Set-Content -Encoding UTF8 "$root\secrets.json"
[IO.File]::WriteAllText("$dir\.env", "TWITCH_BOT_USERNAME=$($BotUsername.ToLower())`nTWITCH_BOT_OAUTH=oauth:$Token`nLOG_DIR=$root\logs`n", $utf8)

$cfg = [IO.File]::ReadAllText("$dir\config.json")
if ($cfg -match '"chat":\s*null') {
    # Installed without Twitch: the chat block has no channel in it yet.
    $chat = [IO.File]::ReadAllText("$dir\chat-block.json").Trim().Replace('"username": ""', "`"username`": `"$channel`"").Replace('"admins": [""]', "`"admins`": [`"$channel`"]")
    $cfg = $cfg -replace '"chat":\s*null', ('"chat": ' + $chat)
    $null = $cfg | ConvertFrom-Json
    [IO.File]::WriteAllText("$dir\config.json", $cfg, $utf8)
}
# The watchdog restarts NOALBS within ~10 seconds with the new settings.
Get-Process -Name noalbs -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host 'Chat commands enabled. Type !bitrate in your Twitch chat in ~15 seconds to test.'
