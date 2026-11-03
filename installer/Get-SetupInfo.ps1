# Used by Setup.exe (installer/IRLHomekit.iss) before its pages are shown: what's already installed, and what's in
# your regular OBS (scene collections, profiles, browser sources), so the wizard can offer them in lists.
# Writes UTF-8 (with BOM) lines "kind<TAB>value[<TAB>value]" to -Out. Read only: changes nothing.
param(
    [Parameter(Mandatory)] [string] $Out,
    [string] $InstallDir = 'C:\IRLHomekit',
    [string] $BaseObsConfigDir = "$env:APPDATA\obs-studio",
    [string] $ObsName = 'IRL Homekit'
)
$ErrorActionPreference = 'Continue'
$lines = New-Object System.Collections.Generic.List[string]
function Add([string[]] $v) { $lines.Add((($v | ForEach-Object { "$_" -replace "[`t`r`n]", ' ' }) -join "`t")) }

# Existing install: its version and previous answers (an update keeps them; the wizard shows them).
if (Test-Path "$InstallDir\settings.json") {
    $prev = Get-Content "$InstallDir\settings.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    Add 'installed', $(if (Test-Path "$InstallDir\VERSION") { (Get-Content "$InstallDir\VERSION" -Raw).Trim() } else { 'unknown' })
    foreach ($k in 'twitchChannel', 'kickChannel', 'youtubeChannelId', 'domain', 'dashboardOnIp', 'duckdnsName', 'relayHost', 'baseCollection', 'baseObsConfigDir') { if ($prev.$k) { Add 'prev', $k, $prev.$k } }
    if ($prev.baseObsConfigDir) { $BaseObsConfigDir = $prev.baseObsConfigDir }
    # The custom stream destination (obs-multi-rtmp target 1003): its name and server; only whether a key is set.
    $mr = Join-Path $prev.obsConfigDir ('basic\profiles\' + ("$($prev.obsProfile)" -replace '[^A-Za-z0-9_\-]', '_') + '\obs-multi-rtmp.json')
    if ($prev.obsConfigDir -and (Test-Path $mr)) {
        $ct = (Get-Content $mr -Raw -Encoding UTF8 | ConvertFrom-Json).targets | Where-Object { "$($_.id)" -eq '1003' } | Select-Object -First 1
        if ($ct.'service-param'.server) {
            Add 'prev', 'customName', $ct.name; Add 'prev', 'customServer', $ct.'service-param'.server
            if ($ct.'service-param'.key) { Add 'prev', 'hasCustomKey', '1' }
        }
    }
}
$sec = if (Test-Path "$InstallDir\secrets.json") { Get-Content "$InstallDir\secrets.json" -Raw -Encoding UTF8 | ConvertFrom-Json }
if ($sec.duckdnsToken) { Add 'prev', 'hasDuckdnsToken', '1' }
if ($sec.dashboardUser) { Add 'prev', 'dashboardUser', $sec.dashboardUser }

# The relay password. Setup needs it before installing: it goes into the relay VM's setup script, which you paste
# into Oracle Cloud while the wizard waits for the VM's address. Reused if this PC already has one.
$token = $sec.relayToken
if (-not $token) {
    $c = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray(); $b = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); $token = -join ($b | ForEach-Object { $c[$_ % $c.Length] })
}
Add 'relaytoken', $token

# Your regular OBS (read only).
$scenesDir = Join-Path $BaseObsConfigDir 'basic\scenes'
foreach ($f in Get-ChildItem $scenesDir -Filter *.json -ErrorAction SilentlyContinue) {
    try { $j = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
    if (-not $j.name -or $j.name -eq $ObsName) { continue }
    Add 'collection', $j.name
    foreach ($src in @($j.sources | Where-Object id -eq 'browser_source')) { Add 'browser', $j.name, $src.name }
}
foreach ($d in Get-ChildItem (Join-Path $BaseObsConfigDir 'basic\profiles') -Directory -ErrorAction SilentlyContinue) {
    $n = (Get-Content "$($d.FullName)\basic.ini" -ErrorAction SilentlyContinue | Where-Object { $_ -like 'Name=*' } | Select-Object -First 1) -replace '^Name='
    if ($n -and $n -ne $ObsName) { Add 'profile', $n }
}
[IO.File]::WriteAllLines($Out, $lines, (New-Object Text.UTF8Encoding $true))
