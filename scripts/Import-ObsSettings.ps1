# Imports everything from your regular OBS into the IRL Homekit OBS: all profiles (stream keys, encoder settings),
# scene collections, hotkeys, window layout, plugin settings and, when both are the same OBS version, your extra
# plugins. Your regular OBS is only read from, never changed.
#
# The IRL Homekit profile, the IRL scene collection and the IRL WebSocket settings are kept as they are, and the
# current IRL Homekit OBS settings are backed up first (to <install folder>\obs-config-backup).
# Run it from the Start menu: "IRL Homekit - Import from OBS". Close the IRL Homekit OBS window first.
param(
    [string] $InstallDir = (Split-Path $PSScriptRoot -Parent),
    [string] $From = "$env:APPDATA\obs-studio",
    [switch] $Yes,
    [switch] $NoPlugins
)
$ErrorActionPreference = 'Stop'
$settings = Get-Content "$InstallDir\settings.json" -Raw | ConvertFrom-Json
$to = $settings.obsConfigDir
$irlObs = Join-Path $settings.obsDir 'obs64.exe'
$name = $settings.obsCollection
$irlFile = ($name -replace '[^A-Za-z0-9_\-]', '_')
$irlProfile = ($settings.obsProfile -replace '[^A-Za-z0-9_\-]', '_')

if (-not (Test-Path $From)) { throw "No regular OBS settings found in $From." }
if (Get-Process obs64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $irlObs }) {
    throw 'Close the IRL Homekit OBS window first (it saves its settings when it closes), then run this again.'
}
if (-not $Yes) {
    Write-Host "`nImport from your regular OBS" -ForegroundColor Cyan
    Write-Host "Copies all profiles (with stream keys), scene collections, hotkeys, layout and plugin settings from"
    Write-Host "your regular OBS into the IRL Homekit OBS. Your IRL Homekit profile and IRL scenes are kept."
    Write-Host "Your regular OBS isn't changed, and the current IRL Homekit OBS settings are backed up first."
    if ((Read-Host 'Import now? (y/N)') -notmatch '^y') { Write-Host 'Nothing was changed.'; return }
}

# 1. Back up the IRL Homekit OBS settings.
$skip = 'logs', 'crashes', 'profiler_data', 'updates', '.sentinel', 'safe_mode', 'plugin_manager'
if (Test-Path $to) {
    $backup = Join-Path $InstallDir ('obs-config-backup\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force $backup | Out-Null
    Get-ChildItem $to -Force | Where-Object { $_.Name -notin $skip } | Copy-Item -Destination $backup -Recurse -Force
    Write-Host "  backed up the IRL Homekit OBS settings to $backup"
}

# 2. Copy settings, leaving the IRL profile, IRL scene collection and IRL WebSocket config alone.
New-Item -ItemType Directory -Force $to | Out-Null
foreach ($item in Get-ChildItem $From -Force | Where-Object { $_.Name -notin $skip }) {
    switch ($item.Name) {
        'basic' {
            New-Item -ItemType Directory -Force "$to\basic\profiles", "$to\basic\scenes" | Out-Null
            Get-ChildItem "$($item.FullName)\profiles" -Directory -ErrorAction SilentlyContinue | Where-Object Name -ne $irlProfile |
                Copy-Item -Destination "$to\basic\profiles\" -Recurse -Force
            Get-ChildItem "$($item.FullName)\scenes" -File -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -notlike "$irlFile*" } |
                Copy-Item -Destination "$to\basic\scenes\" -Force
        }
        'plugin_config' {
            # Your regular OBS may be open and holding some of these files (its browser's cookies), so files in use
            # are skipped instead of stopping the import. Browser caches aren't worth copying.
            foreach ($p in Get-ChildItem $item.FullName -Force | Where-Object Name -ne 'obs-websocket') {
                if ($p.PSIsContainer) {
                    & robocopy.exe $p.FullName "$to\plugin_config\$($p.Name)" /E /R:0 /W:0 /NFL /NDL /NJH /NJS /NP /XD Cache 'Code Cache' GPUCache DawnCache DawnGraphiteCache | Out-Null
                } else {
                    New-Item -ItemType Directory -Force "$to\plugin_config" | Out-Null
                    Copy-Item $p.FullName "$to\plugin_config\" -Force -ErrorAction SilentlyContinue
                }
            }
        }
        default { Copy-Item $item.FullName "$to\" -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
& "$PSScriptRoot\Set-ObsUserIni.ps1" -ConfigDir $to -ObsName $name
$n = @(Get-ChildItem "$to\basic\scenes" -Filter *.json).Count; $pc = @(Get-ChildItem "$to\basic\profiles" -Directory).Count
Write-Host "  imported settings: $pc profiles, $n scene collections (IRL Homekit ones kept)"

# 3. Extra plugins, only when the regular OBS is the same version (plugins are built for one OBS version).
if (-not $NoPlugins) {
    $regDir = (Get-ItemProperty 'HKLM:\SOFTWARE\OBS Studio' -ErrorAction SilentlyContinue).'(default)'
    if (-not $regDir) { $regDir = 'C:\Program Files\obs-studio' }
    $regExe = Join-Path $regDir 'bin\64bit\obs64.exe'
    $irlRoot = Split-Path (Split-Path $settings.obsDir -Parent) -Parent
    if (-not (Test-Path $regExe)) {
        Write-Host '  plugins: regular OBS install not found, skipped'
    } elseif ((Get-Item $regExe).VersionInfo.ProductVersion -ne (Get-Item $irlObs).VersionInfo.ProductVersion) {
        Write-Host ("  plugins: skipped (regular OBS is {0}, IRL Homekit OBS is {1}; install them into {2}\obs-plugins yourself)" -f `
            (Get-Item $regExe).VersionInfo.ProductVersion, (Get-Item $irlObs).VersionInfo.ProductVersion, $irlRoot) -ForegroundColor Yellow
    } else {
        # Plugins live in two places: inside the OBS folder, and (newer installers) C:\ProgramData\obs-studio\plugins.
        # The portable IRL Homekit OBS only loads its own folder, so both kinds are copied there.
        $added = @()
        New-Item -ItemType Directory -Force "$irlRoot\obs-plugins\64bit", "$irlRoot\data\obs-plugins" | Out-Null
        function Add-Plugin($dll, $dataDir) {
            # Skip what this OBS already has (OBS 33+ keeps its own plugins in core\<name>).
            if ((Test-Path "$irlRoot\obs-plugins\64bit\$($dll.Name)") -or (Test-Path "$irlRoot\core\$($dll.BaseName)")) { return }
            Copy-Item $dll.FullName "$irlRoot\obs-plugins\64bit\" -Force
            if ($dataDir -and (Test-Path $dataDir) -and -not (Test-Path "$irlRoot\data\obs-plugins\$($dll.BaseName)")) {
                Copy-Item $dataDir "$irlRoot\data\obs-plugins\$($dll.BaseName)" -Recurse -Force
            }
            $script:added += $dll.BaseName
        }
        foreach ($dll in Get-ChildItem "$regDir\obs-plugins\64bit" -Filter *.dll -ErrorAction SilentlyContinue) { Add-Plugin $dll "$regDir\data\obs-plugins\$($dll.BaseName)" }
        foreach ($p in Get-ChildItem "$env:ProgramData\obs-studio\plugins" -Directory -ErrorAction SilentlyContinue) {
            if (Test-Path "$($p.FullName)\bin\64bit") {
                # Older plugin layout: <name>\bin\64bit\<name>.dll + <name>\data
                foreach ($dll in Get-ChildItem "$($p.FullName)\bin\64bit" -Filter *.dll -ErrorAction SilentlyContinue) { Add-Plugin $dll "$($p.FullName)\data" }
            } elseif ((Get-ChildItem $p.FullName -Filter *.dll -ErrorAction SilentlyContinue) -and -not (Test-Path "$irlRoot\plugins\$($p.Name)")) {
                # OBS 33+ layout: <name>\<name>.dll + <name>\data. The portable OBS loads these from obs\plugins\<name>.
                New-Item -ItemType Directory -Force "$irlRoot\plugins" | Out-Null
                Copy-Item $p.FullName "$irlRoot\plugins\" -Recurse -Force
                $added += $p.Name
            }
        }
        Write-Host "  plugins: $(if ($added) { 'copied ' + ($added -join ', ') } else { 'none extra to copy' })"
        Write-Host '  (A plugin that also fails in your regular OBS needs an update from its author for this OBS version.)'
    }
}
Write-Host "`nDone. Open IRL Homekit to use them." -ForegroundColor Green
