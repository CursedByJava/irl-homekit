# Builds the IRL Homekit OBS scene collection: IRL LIVE / LOW / BRB (+ Backup variants) wired to the phone feeds.
# With -BaseCollection it starts from a copy of one of your existing collections (that collection is not modified)
# and reuses its overlays; without it, it starts from an empty collection.
param(
    [string] $Name = 'IRL Homekit',
    [string] $BaseCollection = '',
    # Where the IRL Homekit collection is written (IRL Homekit's own OBS) ...
    [string] $ObsConfigDir = "$env:APPDATA\obs-studio",
    # ... and where -BaseCollection is read from (your normal OBS).
    [string] $BaseConfigDir = $ObsConfigDir,
    [int] $Width = 1920,
    [int] $Height = 1080,
    # Sources from the base collection to show on top of the IRL scenes (chat, alerts, ...), in that order.
    [string[]] $OverlaySources = @(),
    # A media/image source from the base collection to use as the BRB background (else the animated BRB screen).
    [string] $BrbBackground = '',
    # Folder with the animated screens (brb.html, starting.html, low-bitrate.html).
    [string] $OverlayDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'overlays'),
    [switch] $Force
)
$ErrorActionPreference = 'Stop'
$scenesDir = Join-Path $ObsConfigDir 'basic\scenes'
$dstFile = Join-Path $scenesDir (($Name -replace '[^A-Za-z0-9_\-]', '_') + '.json')
if ((Test-Path $dstFile) -and -not $Force) { throw "$dstFile already exists (use -Force to overwrite)" }

if ($BaseCollection) {
    $baseDir = Join-Path $BaseConfigDir 'basic\scenes'
    $src = Get-ChildItem $baseDir -Filter *.json | Where-Object {
        try { (Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).name -eq $BaseCollection } catch { $false } } | Select-Object -First 1
    if (-not $src) { throw "No OBS scene collection named '$BaseCollection' in $baseDir" }
    $j = Get-Content $src.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    $j = Get-Content (Join-Path $PSScriptRoot '..\templates\blank-collection.json') -Raw | ConvertFrom-Json
    $j.resolution = [pscustomobject]@{ x = $Width; y = $Height }
}
$j.name = $Name
if ($j.sources | Where-Object { $_.name -like 'IRL Phone*' }) { throw "'$BaseCollection' already contains IRL Homekit scenes" }

$MAIN_CANVAS = '6c69626f-6273-4c00-9d88-c5136d61696e'   # OBS's fixed id for the main canvas
function New-Uuid { [guid]::NewGuid().ToString() }

function New-Source($srcName, $id, $versionedId, $settings, $mixers) {
    [pscustomobject][ordered]@{
        prev_ver = 553648128; name = $srcName; uuid = (New-Uuid); id = $id; versioned_id = $versionedId
        settings = [pscustomobject]$settings
        mixers = $mixers; sync = 0; flags = 0; volume = 1.0; balance = 0.5; enabled = $true; muted = $false
        'push-to-mute' = $false; 'push-to-mute-delay' = 0; 'push-to-talk' = $false; 'push-to-talk-delay' = 0
        hotkeys = [pscustomobject]@{}; deinterlace_mode = 0; deinterlace_field_order = 0
        monitoring_type = 0; monitoring_enabled = $false; private_settings = [pscustomobject]@{}
    }
}

function New-SceneItem($src, $itemId, [hashtable]$t) {
    $i = [ordered]@{
        name = $src.name; source_uuid = $src.uuid; visible = $true; locked = $true; rot = 0.0
        align = 5; bounds_type = 0; bounds_align = 0; bounds_crop = $false
        crop_left = 0; crop_top = 0; crop_right = 0; crop_bottom = 0; id = $itemId; group_item_backup = $false
        pos = [pscustomobject]@{ x = 0.0; y = 0.0 }; scale = [pscustomobject]@{ x = 1.0; y = 1.0 }
        bounds = [pscustomobject]@{ x = 0.0; y = 0.0 }
        scale_filter = 'disable'; blend_method = 'default'; blend_type = 'normal'
        show_transition = [pscustomobject]@{ duration = 300 }; hide_transition = [pscustomobject]@{ duration = 300 }
        private_settings = [pscustomobject]@{}
    }
    foreach ($k in $t.Keys) { $i[$k] = $t[$k] }
    [pscustomobject]$i
}

$fullFrame = @{ bounds_type = 2; bounds_align = 0; bounds = [pscustomobject]@{ x = [double]$Width; y = [double]$Height } }
$center = { param($y) @{ align = 0; pos = [pscustomobject]@{ x = [double]($Width / 2); y = [double]$y } } }

# Reuse an existing source: copy the transform it has in the first scene that shows it, else fill the canvas.
function Use-Existing($srcName, $itemId) {
    $s = $j.sources | Where-Object { $_.name -eq $srcName -and $_.id -ne 'scene' } | Select-Object -First 1
    if (-not $s) { Write-Warning "Source '$srcName' not found in '$BaseCollection', skipping it"; return $null }
    foreach ($sc in $j.sources | Where-Object id -eq 'scene') {
        $it = $sc.settings.items | Where-Object source_uuid -eq $s.uuid | Select-Object -First 1
        if ($it) { $c = $it | ConvertTo-Json -Depth 20 | ConvertFrom-Json; $c.id = $itemId; $c.visible = $true; return $c }
    }
    New-SceneItem $s $itemId $fullFrame
}

function New-Scene($sceneName, $items) {
    $items = @($items | Where-Object { $_ })
    for ($k = 0; $k -lt $items.Count; $k++) { $items[$k].id = $k + 1 }
    $s = New-Source $sceneName 'scene' 'scene' @{ id_counter = $items.Count; custom_size = $false; items = $items } 0
    $s | Add-Member canvas_uuid $MAIN_CANVAS
    $s
}

# Phone feeds. Bonded = go-irl's SRTLA output; Backup = MediaMTX (plain SRT or RTMP from the phone).
$feedCommon = @{ is_local_file = $false; input_format = 'mpegts'; restart_on_activate = $false; close_when_inactive = $false
    hw_decode = $true; reconnect_delay_sec = 1; buffering_mb = 1; looping = $false }
$bondedSettings = $feedCommon.Clone(); $bondedSettings.input = 'udp://127.0.0.1:5002'
# MediaMTX only lets OBS read the backup feed with its own login (secrets.json next to the overlays folder), not
# just for coming from this PC.
$readId = 'read:live'
$secFile = Join-Path (Split-Path $OverlayDir -Parent) 'secrets.json'
if (Test-Path $secFile) {
    $sec = Get-Content $secFile -Raw | ConvertFrom-Json
    if ($sec.mediamtxReadUser -and $sec.mediamtxReadPass) { $readId = "read:live:$($sec.mediamtxReadUser):$($sec.mediamtxReadPass)" }
}
$backupSettings = $feedCommon.Clone(); $backupSettings.input = "srt://127.0.0.1:8890?streamid=$readId"; $backupSettings.reconnect_delay_sec = 2
$bonded = New-Source 'IRL Phone (Bonded)' 'ffmpeg_source' 'ffmpeg_source' $bondedSettings 255
$backup = New-Source 'IRL Phone (Backup)' 'ffmpeg_source' 'ffmpeg_source' $backupSettings 255

$font = { param($size) [pscustomobject]@{ face = 'Arial'; style = 'Bold'; size = $size; flags = 1 } }
$brbText = New-Source 'IRL BRB Text' 'text_gdiplus' 'text_gdiplus_v3' @{ text = 'BE RIGHT BACK'; font = (& $font 180); align = 'center'
    outline = $true; outline_size = 8; outline_color = 4278190080 } 0
$brbSub = New-Source 'IRL BRB Subtext' 'text_gdiplus' 'text_gdiplus_v3' @{ text = 'Signal dropped - reconnecting...'; font = (& $font 64); align = 'center'
    outline = $true; outline_size = 5; outline_color = 4278190080 } 0
# Animated full-screen scenes and the low-bitrate banner (local HTML pages rendered by OBS's browser source).
$overlayPath = { param($f) ((Resolve-Path (Join-Path $OverlayDir $f)).Path -replace '\\', '/') }
$page = { param($srcName, $file) New-Source $srcName 'browser_source' 'browser_source' @{ is_local_file = $true; local_file = (& $overlayPath $file)
    width = $Width; height = $Height; fps = 60; fps_custom = $true; css = ''; shutdown = $false; restart_when_active = $false; reroute_audio = $false } 0 }
$brbScreen = & $page 'IRL BRB Screen' 'brb.html'
$startScreen = & $page 'IRL Starting Soon Screen' 'starting.html'
$lowOverlay = & $page 'IRL Low Bitrate Overlay' 'low-bitrate.html'
$newSources = @($bonded, $backup, $brbScreen, $startScreen, $lowOverlay)

# BRB: the animated screen by default; or your own media source behind simple text if you pass -BrbBackground.
$brbItems = @()
if ($BrbBackground) { $brbBg = Use-Existing $BrbBackground 0 }
if ($BrbBackground -and $brbBg) {
    $newSources += @($brbText, $brbSub)
    $brbItems = @($brbBg, (New-SceneItem $brbText 0 (& $center ($Height * 0.435))), (New-SceneItem $brbSub 0 (& $center ($Height * 0.575))))
} else {
    $brbItems = @((New-SceneItem $brbScreen 0 @{}))
}
$overlays = { @($OverlaySources | ForEach-Object { Use-Existing $_ 0 }) }

$live = New-Scene 'IRL LIVE' (@((New-SceneItem $bonded 0 $fullFrame)) + (& $overlays))
$low = New-Scene 'IRL LOW' (@((New-SceneItem $bonded 0 $fullFrame), (New-SceneItem $lowOverlay 0 @{})) + (& $overlays))
$liveB = New-Scene 'IRL LIVE (Backup)' (@((New-SceneItem $backup 0 $fullFrame)) + (& $overlays))
$lowB = New-Scene 'IRL LOW (Backup)' (@((New-SceneItem $backup 0 $fullFrame), (New-SceneItem $lowOverlay 0 @{})) + (& $overlays))
$brb = New-Scene 'IRL BRB' ($brbItems + (& $overlays))
$starting = New-Scene 'IRL Starting Soon' (@((New-SceneItem $startScreen 0 @{})) + (& $overlays))

# Free capture cards while their scenes are not on screen (the PC may also be used for desktop streams).
foreach ($s in $j.sources | Where-Object id -eq 'dshow_input') { $s.settings | Add-Member -Force deactivate_when_not_showing $true }

$j.sources = @($j.sources) + $newSources + @($starting, $live, $low, $brb, $liveB, $lowB)
$existing = @($j.scene_order | ForEach-Object name)
$j.scene_order = @(@('IRL Starting Soon', 'IRL LIVE', 'IRL LOW', 'IRL BRB', 'IRL LIVE (Backup)', 'IRL LOW (Backup)') + $existing | ForEach-Object { [pscustomobject]@{ name = $_ } })
$j.current_scene = 'IRL BRB'; $j.current_program_scene = 'IRL BRB'

$json = $j | ConvertTo-Json -Depth 100
$null = $json | ConvertFrom-Json
New-Item -ItemType Directory -Force $scenesDir | Out-Null
[IO.File]::WriteAllText($dstFile, $json, (New-Object Text.UTF8Encoding $false))
Write-Host "Scene collection '$Name' written to $dstFile"
