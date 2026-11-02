# Makes the IRL Homekit OBS open straight into the IRL profile and scene collection, without the first-run
# wizard, in the IRL Homekit skin, and with the dashboard and Studio as panels (Docks menu). Keeps every other
# setting in user.ini.
param(
    [Parameter(Mandatory)] [string] $ConfigDir,
    [string] $ObsName = 'IRL Homekit'
)
$ErrorActionPreference = 'Stop'
$file = Join-Path $ConfigDir 'user.ini'
$lines = New-Object System.Collections.Generic.List[string]
if (Test-Path $file) { foreach ($l in [IO.File]::ReadAllLines($file)) { $lines.Add($l) } }

function Get-Ini($section, $key) {
    $in = $false
    foreach ($l in $lines) {
        if ($l -match '^\[(.+)\]$') { $in = $Matches[1] -eq $section; continue }
        if ($in -and $l -like "$key=*") { return $l.Substring($key.Length + 1) }
    }
}
function Set-Ini($section, $key, $value) {
    $in = $false; $last = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\[(.+)\]$') { if ($in) { break }; $in = $Matches[1] -eq $section; if ($in) { $last = $i }; continue }
        if ($in) {
            if ($lines[$i] -like "$key=*") { $lines[$i] = "$key=$value"; return }
            if ($lines[$i].Trim()) { $last = $i }
        }
    }
    if ($last -lt 0) { if ($lines.Count -and $lines[$lines.Count - 1].Trim()) { $lines.Add('') }; $lines.Add("[$section]"); $lines.Add("$key=$value"); return }
    $lines.Insert($last + 1, "$key=$value")
}

$dir = $ObsName -replace '[^A-Za-z0-9_\-]', '_'
Set-Ini 'General' 'FirstRun' 'true'
Set-Ini 'General' 'WarnedAboutClosingDocks' 'true'
Set-Ini 'BasicWindow' 'SysTrayEnabled' 'true'
# Closing the window quits (and with it IRL Homekit); it never hides in the tray.
Set-Ini 'BasicWindow' 'SysTrayMinimizeToTray' 'false'
# The IRL Homekit skin (templates/IRL_Homekit.ovt), so this OBS never looks like your regular one.
Set-Ini 'Appearance' 'Theme' 'com.irlhomekit.Yami.IRLHomekit'
Set-Ini 'Basic' 'Profile' $ObsName
Set-Ini 'Basic' 'ProfileDir' $dir
Set-Ini 'Basic' 'SceneCollection' $ObsName
Set-Ini 'Basic' 'SceneCollectionFile' "$dir.json"

$docks = @(); $raw = Get-Ini 'BasicWindow' 'ExtraBrowserDocks'
if ($raw) { try { $docks = @($raw | ConvertFrom-Json | Where-Object { $_.url }) } catch { $docks = @() } }   # drop empty panels
foreach ($d in @(@('IRL Homekit', 'http://localhost:8090/'), @('IRL Studio', 'http://localhost:8090/studio'))) {
    if (-not ($docks | Where-Object { $_.url -eq $d[1] })) {
        $docks += [pscustomobject][ordered]@{ title = $d[0]; url = $d[1]; uuid = [guid]::NewGuid().ToString() }
    }
}
Set-Ini 'BasicWindow' 'ExtraBrowserDocks' (ConvertTo-Json -Compress -InputObject @($docks))

New-Item -ItemType Directory -Force $ConfigDir | Out-Null
[IO.File]::WriteAllLines($file, $lines, (New-Object Text.UTF8Encoding $true))
