# Saves an "IRL Homekit diagnostics" zip on your desktop to attach to a bug report: version, settings, service
# status and recent logs. Passwords, tokens and stream keys are removed (secrets.json and PHONE-SETUP.md are never
# included, and any of their values found in the logs are replaced with [redacted]). Have a look before sharing.
param([string] $InstallDir = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
$settings = Get-Content "$InstallDir\settings.json" -Raw | ConvertFrom-Json
$secrets = Get-Content "$InstallDir\secrets.json" -Raw | ConvertFrom-Json
$secretValues = @($secrets.PSObject.Properties | ForEach-Object { "$($_.Value)" } | Where-Object { $_.Length -ge 6 } | Sort-Object Length -Descending)
function Hide-Secrets([string] $text) {
    foreach ($v in $secretValues) { $text = $text.Replace($v, '[redacted]') }
    # Stream keys and tokens in OBS / tool logs
    $text -replace '(live_[0-9a-z_]{10,}|sk_[A-Za-z0-9]{10,}|(?i)(key|token|secret|password)(["'':= ]+)[^\s",]{8,})', '[redacted]'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$work = Join-Path $env:TEMP "irlhk-diag-$stamp"; New-Item -ItemType Directory -Force $work | Out-Null
$summary = [System.Collections.Generic.List[string]]::new()
$summary.Add("IRL Homekit $((Get-Content "$InstallDir\VERSION" -Raw -ErrorAction SilentlyContinue).Trim())  -  $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$summary.Add("Windows: $((Get-CimInstance Win32_OperatingSystem).Caption) $((Get-CimInstance Win32_OperatingSystem).Version)")
$summary.Add("GPU: $((Get-CimInstance Win32_VideoController).Name -join ', ')")
$summary.Add("Node: $(& node --version 2>$null)")
$summary.Add("IRL OBS: $((Get-Item (Join-Path $settings.obsDir 'obs64.exe') -ErrorAction SilentlyContinue).VersionInfo.ProductVersion)")
$summary.Add('')
$summary.Add('Processes:')
foreach ($n in 'obs64', 'go-irl', 'mediamtx', 'noalbs', 'caddy') {
    $p = Get-Process $n -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$InstallDir\*" }
    $summary.Add(('  {0,-9} {1}' -f $n, $(if ($p) { "running since $(@($p)[0].StartTime)" } else { 'not running' })))
}
$summary.Add("  dashboard  $(if (Get-NetTCPConnection -LocalPort 8090 -State Listen -ErrorAction SilentlyContinue) { 'listening on 8090' } else { 'not running' })")
$summary.Add('')
$summary.Add('Tasks:')
Get-ScheduledTask -TaskName 'IRL Homekit*' -ErrorAction SilentlyContinue | ForEach-Object { $summary.Add("  $($_.TaskName): $($_.State)") }
[IO.File]::WriteAllLines("$work\summary.txt", $summary)

Copy-Item "$InstallDir\settings.json" "$work\settings.json"
New-Item -ItemType Directory -Force "$work\logs" | Out-Null
foreach ($f in Get-ChildItem "$InstallDir\logs" -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.log', '.txt' }) {
    $lines = Get-Content $f.FullName -Tail 2000 -ErrorAction SilentlyContinue
    [IO.File]::WriteAllText("$work\logs\$($f.Name)", (Hide-Secrets ($lines -join "`r`n")))
}
$obsLogs = Join-Path $settings.obsConfigDir 'logs'
foreach ($f in Get-ChildItem $obsLogs -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3) {
    [IO.File]::WriteAllText("$work\logs\obs-$($f.Name)", (Hide-Secrets ([IO.File]::ReadAllText($f.FullName))))
}

$zip = Join-Path ([Environment]::GetFolderPath('Desktop')) "IRL Homekit diagnostics $stamp.zip"
Compress-Archive -Path "$work\*" -DestinationPath $zip -Force
Remove-Item -LiteralPath $work -Recurse -Force
Write-Host "Saved: $zip" -ForegroundColor Green
Write-Host 'Attach it to your bug report: https://github.com/CursedByJava/irl-homekit/issues/new/choose'
Start-Process explorer.exe "/select,`"$zip`""
