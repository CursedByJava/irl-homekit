# Re-imports your scenes: rebuilds the IRL Homekit scene collection from your base collection (settings.json
# "baseCollection"), so overlay/layout changes you make there show up on the IRL scenes.
# Edit your normal collection in OBS, then run this (desktop shortcut "IRL Homekit - Update scenes" or the dashboard).
# The previous IRL Homekit collection is backed up next to it first. Refuses to run while streaming or recording.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$settings = Get-Content "$root\settings.json" -Raw | ConvertFrom-Json
$secrets = Get-Content "$root\secrets.json" -Raw | ConvertFrom-Json
$obsConfig = "$env:APPDATA\obs-studio"
$name = $settings.obsCollection
$base = $settings.baseCollection
if (-not $base) { throw 'No base collection set. Add "baseCollection": "<your collection name>" to settings.json.' }

function Connect-Obs {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    try { $ws.ConnectAsync([uri]'ws://127.0.0.1:4455', [Threading.CancellationToken]::None).Wait(5000) | Out-Null } catch { return $null }
    if ($ws.State -ne 'Open') { return $null }
    $script:ws = $ws
    $h = Recv
    $sha = { param($t) [Convert]::ToBase64String([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($t))) }
    Send @{ op = 1; d = @{ rpcVersion = 1; eventSubscriptions = 0; authentication = (& $sha ((& $sha ($secrets.obsWebsocketPassword + $h.d.authentication.salt)) + $h.d.authentication.challenge)) } }
    $null = Recv
    $ws
}
function Recv {
    $buf = New-Object byte[] 1048576; $ms = New-Object IO.MemoryStream
    do { $r = $script:ws.ReceiveAsync((New-Object ArraySegment[byte] (, $buf)), [Threading.CancellationToken]::None).Result; $ms.Write($buf, 0, $r.Count) } while (-not $r.EndOfMessage)
    [Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json
}
function Send($o) { $b = [Text.Encoding]::UTF8.GetBytes(($o | ConvertTo-Json -Depth 10 -Compress)); $script:ws.SendAsync((New-Object ArraySegment[byte] (, $b)), 'Text', $true, [Threading.CancellationToken]::None).Wait() }
$script:rid = 0
function Req($type, $data = @{}) {
    $script:rid++; Send @{ op = 6; d = @{ requestType = $type; requestId = "u$script:rid"; requestData = $data } }
    do { $m = Recv } while ($m.op -ne 7)
    if (-not $m.d.requestStatus.result) { throw "OBS refused ${type}: $($m.d.requestStatus.comment)" }
    $m.d.responseData
}

$ws = Connect-Obs
if ($ws) {
    if ((Req 'GetStreamStatus').outputActive -or (Req 'GetRecordStatus').outputActive) {
        throw 'You are live or recording. End the stream first: updating scenes swaps OBS collections for a few seconds.'
    }
    $list = Req 'GetSceneCollectionList'
    if ($list.sceneCollections -notcontains $base) { throw "OBS has no scene collection named '$base' (settings.json baseCollection)." }
    # Leave the IRL collection so OBS saves it and lets go of the file.
    if ($list.currentSceneCollectionName -eq $name) { Write-Host "Switching OBS to '$base' for a moment..."; $null = Req 'SetCurrentSceneCollection' @{ sceneCollectionName = $base }; Start-Sleep 3 }
} else {
    Write-Host 'OBS is not running; updating the file only.'
}

$file = Join-Path $obsConfig ('basic\scenes\' + ($name -replace '[^A-Za-z0-9_\-]', '_') + '.json')
if (Test-Path $file) {
    $backupDir = Join-Path $root 'scene-backups'; New-Item -ItemType Directory -Force $backupDir | Out-Null
    Copy-Item $file (Join-Path $backupDir ('{0}-{1}.json' -f ($name -replace '\W', '_'), (Get-Date -Format 'yyyyMMdd-HHmmss')))
    Get-ChildItem $backupDir -Filter *.json | Sort-Object LastWriteTime -Descending | Select-Object -Skip 20 | Remove-Item -Force
}
& "$PSScriptRoot\New-IRLScenes.ps1" -Name $name -BaseCollection $base -ObsConfigDir $obsConfig `
    -OverlaySources @($settings.overlayInputs) -BrbBackground $settings.brbBackground -Force

if ($ws) {
    $null = Req 'SetCurrentSceneCollection' @{ sceneCollectionName = $name }; Start-Sleep 3
    $null = Req 'SetCurrentProgramScene' @{ sceneName = 'IRL BRB' }
    $ws.Dispose()
}
Write-Host "Done. '$name' now matches '$base' plus the IRL scenes. Backups: $root\scene-backups" -ForegroundColor Green
