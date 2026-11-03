# Checks GitHub for a newer IRL Homekit and installs it.
#   Start menu "IRL Homekit - Check for updates"   asks before updating
#   -Prompt   (the app, when you open it)          shows a Windows "Update now?" box if there's an update
#   -Yes      (the dashboard's Update button)      updates without asking
#   -Check                                          only reports; returns the result
# Updating downloads the release from GitHub, closes IRL Homekit, runs its installer with your saved answers (nothing
# is asked, nothing is lost) and reopens IRL Homekit. It refuses while you're live or recording.
param(
    [string] $InstallDir = (Split-Path $PSScriptRoot -Parent),
    [switch] $Check, [switch] $Prompt, [switch] $Yes
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # no grey progress box over the window (and much faster downloads)
$repoSlug = 'CursedByJava/irl-homekit'
$settings = Get-Content "$InstallDir\settings.json" -Raw | ConvertFrom-Json
# Copies installed before version numbers existed were all betas.
$current = if (Test-Path "$InstallDir\VERSION") { (Get-Content "$InstallDir\VERSION" -Raw).Trim() } else { '0.0.0-beta' }

# Semantic versions: 1.2.3 > 1.2.3-beta.4 > 1.2.3-beta.3
function ConvertTo-Ver($v) {
    $v = "$v".Trim() -replace '^v', ''
    $core, $pre = $v -split '-', 2
    $n = @(($core -split '\.') | ForEach-Object { [int]$_ }) + @(0, 0, 0)
    [pscustomobject]@{ Text = $v; Nums = $n[0..2]; Pre = if ($pre) { @($pre -split '\.') } else { @() } }
}
function Compare-Ver($a, $b) {
    for ($i = 0; $i -lt 3; $i++) { if ($a.Nums[$i] -ne $b.Nums[$i]) { return [Math]::Sign($a.Nums[$i] - $b.Nums[$i]) } }
    if (-not $a.Pre.Count -and -not $b.Pre.Count) { return 0 }
    if (-not $a.Pre.Count) { return 1 }; if (-not $b.Pre.Count) { return -1 }
    for ($i = 0; $i -lt [Math]::Max($a.Pre.Count, $b.Pre.Count); $i++) {
        if ($i -ge $a.Pre.Count) { return -1 }; if ($i -ge $b.Pre.Count) { return 1 }
        $x = $a.Pre[$i]; $y = $b.Pre[$i]; $xn = $x -match '^\d+$'; $yn = $y -match '^\d+$'
        if ($xn -and $yn) { if ([int]$x -ne [int]$y) { return [Math]::Sign([int]$x - [int]$y) } }
        elseif ($x -ne $y) { return $(if ($xn) { -1 } elseif ($yn) { 1 } else { [string]::CompareOrdinal($x, $y) }) }
    }
    0
}

function Get-Update {
    $cur = ConvertTo-Ver $current
    # Betas get beta updates; once you're on a stable version you only get stable ones (settings.json "updateChannel" overrides).
    $channel = if ($settings.updateChannel) { $settings.updateChannel } elseif ($cur.Pre.Count) { 'beta' } else { 'stable' }
    $rels = Invoke-RestMethod "https://api.github.com/repos/$repoSlug/releases?per_page=30" -Headers @{ 'User-Agent' = 'IRL-Homekit-updater' } -TimeoutSec 15
    $best = $null
    foreach ($r in $rels) {
        if ($r.draft -or ($r.prerelease -and $channel -ne 'beta')) { continue }
        $v = ConvertTo-Ver $r.tag_name
        if (-not $best -or (Compare-Ver $v $best.Ver) -gt 0) { $best = [pscustomobject]@{ Ver = $v; Release = $r } }
    }
    [pscustomobject]@{
        Current = $current; Latest = $(if ($best) { $best.Ver.Text } else { $current })
        Newer = [bool]($best -and (Compare-Ver $best.Ver $cur) -gt 0)
        Notes = $(if ($best) { "$($best.Release.body)" } else { '' }); Url = $(if ($best) { $best.Release.html_url })
        Zip = $(if ($best) { $best.Release.zipball_url })
    }
}

function Test-Live {
    $port = if ($settings.obsWebsocketPort) { $settings.obsWebsocketPort } else { 4455 }
    $secrets = Get-Content "$InstallDir\secrets.json" -Raw | ConvertFrom-Json
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    try { $ws.ConnectAsync([uri]"ws://127.0.0.1:$port", [Threading.CancellationToken]::None).Wait(3000) | Out-Null } catch { return $false }
    if ($ws.State -ne 'Open') { return $false }
    $recv = { $buf = New-Object byte[] 65536; $r = $ws.ReceiveAsync((New-Object ArraySegment[byte] (, $buf)), [Threading.CancellationToken]::None).Result; [Text.Encoding]::UTF8.GetString($buf, 0, $r.Count) | ConvertFrom-Json }
    $send = { param($o) $b = [Text.Encoding]::UTF8.GetBytes(($o | ConvertTo-Json -Depth 6 -Compress)); $ws.SendAsync((New-Object ArraySegment[byte] (, $b)), 'Text', $true, [Threading.CancellationToken]::None).Wait() }
    $sha = { param($t) [Convert]::ToBase64String([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($t))) }
    $h = & $recv
    & $send @{ op = 1; d = @{ rpcVersion = 1; eventSubscriptions = 0; authentication = (& $sha ((& $sha ($secrets.obsWebsocketPassword + $h.d.authentication.salt)) + $h.d.authentication.challenge)) } }; $null = & $recv
    $live = $false
    foreach ($t in 'GetStreamStatus', 'GetRecordStatus') {
        & $send @{ op = 6; d = @{ requestType = $t; requestId = $t; requestData = @{} } }
        do { $m = & $recv } while ($m.op -ne 7)
        if ($m.d.responseData.outputActive) { $live = $true }
    }
    $ws.Dispose(); $live
}

function Install-Update($u) {
    if (Test-Live) { throw 'You are live or recording. End the stream first, then update.' }
    # The installer needs administrator rights (the app already has them; the Start menu tool asks).
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -InstallDir `"$InstallDir`" -Yes"
        return
    }
    $work = Join-Path $env:TEMP "irlhk-update-$($u.Latest)"
    if (Test-Path $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    New-Item -ItemType Directory -Force $work | Out-Null
    Start-Transcript -Path "$InstallDir\logs\update.log" -Append | Out-Null
    try {
        Write-Host "Updating IRL Homekit $current -> $($u.Latest)"
        Invoke-WebRequest $u.Zip -OutFile "$work\release.zip" -UseBasicParsing -Headers @{ 'User-Agent' = 'IRL-Homekit-updater' }
        Expand-Archive "$work\release.zip" "$work\src" -Force
        $installer = Get-ChildItem "$work\src" -Recurse -Filter install.ps1 | Select-Object -First 1
        if (-not $installer) { throw 'The download does not contain install.ps1.' }
        # Closes IRL Homekit, updates everything with your saved answers, and reopens it.
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer.FullName -InstallDir $InstallDir -NonInteractive
        if ($LASTEXITCODE) { throw "The installer stopped (exit code $LASTEXITCODE). Details: $InstallDir\logs\update.log" }
        Write-Host "IRL Homekit is now $($u.Latest)." -ForegroundColor Green
    } finally { Stop-Transcript | Out-Null }
}

$u = Get-Update
if ($Check) { return $u }
if (-not $u.Newer) {
    if (-not $Prompt) { Write-Host "IRL Homekit $current is up to date." -ForegroundColor Green }
    return
}
if ($Yes) { Install-Update $u; return }

$notes = ($u.Notes -replace '\r', '').Trim(); if ($notes.Length -gt 700) { $notes = $notes.Substring(0, 700) + '...' }
if ($Prompt) {
    Add-Type -AssemblyName System.Windows.Forms
    $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true; ShowInTaskbar = $false }
    $msg = "IRL Homekit $($u.Latest) is available (you have $current).`n`n$notes`n`nUpdate now? IRL Homekit closes and reopens by itself in about 2 minutes."
    if ([System.Windows.Forms.MessageBox]::Show($owner, $msg, 'IRL Homekit update', 'YesNo', 'Information') -eq 'Yes') {
        try { Install-Update $u } catch { [System.Windows.Forms.MessageBox]::Show($owner, "The update didn't run: $($_.Exception.Message)", 'IRL Homekit update', 'OK', 'Warning') | Out-Null }
    }
    return
}
Write-Host "`nIRL Homekit $($u.Latest) is available (you have $current)." -ForegroundColor Cyan
if ($notes) { Write-Host "`n$notes`n" }
Write-Host "Release notes: $($u.Url)"
if ((Read-Host 'Update now? IRL Homekit closes and reopens by itself (Y/n)') -notmatch '^n') { Install-Update $u }
