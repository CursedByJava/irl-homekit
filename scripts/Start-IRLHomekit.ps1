# IRL Homekit watchdog. Started at logon by the "IRL Homekit" scheduled task.
# Keeps OBS (IRL Homekit profile), MediaMTX, go-irl, NOALBS, the dashboard and Caddy running; restarts anything that dies.
# Create a PAUSE file in the install folder to stop it relaunching things (Pause-IRLHomekit.ps1 does this).
$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
$logs = "$root\logs"
$pauseFlag = "$root\PAUSE"
$secrets = Get-Content "$root\secrets.json" -Raw | ConvertFrom-Json
$settings = Get-Content "$root\settings.json" -Raw | ConvertFrom-Json
$obsDir = $settings.obsDir
$node = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
if (-not $node) { $node = 'C:\Program Files\nodejs\node.exe' }

# Only one watchdog at a time.
$mutex = New-Object System.Threading.Mutex($false, 'Global\IRLHomekitWatchdog')
if (-not $mutex.WaitOne(0)) { exit 0 }

function Log($msg) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path "$logs\watchdog.log" -Value $line
}

function Rotate($file) {
    if ((Test-Path $file) -and (Get-Item $file).Length -gt 20MB) { Move-Item $file "$file.old" -Force }
}

function Ensure($name, $exe, $argList, $workDir) {
    if (Get-Process -Name $name -ErrorAction SilentlyContinue) { return }
    Rotate "$logs\$name.out.log"; Rotate "$logs\$name.err.log"
    Log "starting $name"
    $p = @{ FilePath = $exe; WorkingDirectory = $workDir; WindowStyle = 'Hidden'
            RedirectStandardOutput = "$logs\$name.out.log"; RedirectStandardError = "$logs\$name.err.log" }
    if ($argList) { $p.ArgumentList = $argList }
    try { Start-Process @p } catch { Log "failed to start ${name}: $_" }
}

# MediaMTX keeps its log file open, so it can only be rotated by restarting it. Do that only while no phone is connected.
function Rotate-MediamtxLog {
    $file = "$logs\mediamtx.log"
    if (-not (Test-Path $file) -or (Get-Item $file).Length -lt 50MB) { return }
    try { Invoke-RestMethod 'http://127.0.0.1:9997/v3/paths/get/live' -TimeoutSec 3 | Out-Null; return } catch { }
    Log 'rotating mediamtx.log (no phone connected)'
    Get-Process -Name mediamtx -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    Move-Item $file "$file.old" -Force
}

# The dashboard runs on node.exe, which other apps may also use, so check its port instead of the process name.
function Ensure-Dashboard {
    if (Get-NetTCPConnection -LocalPort 8090 -State Listen -ErrorAction SilentlyContinue) { return }
    Rotate "$logs\dashboard.out.log"; Rotate "$logs\dashboard.err.log"
    Log 'starting dashboard'
    try {
        Start-Process -FilePath $node -ArgumentList @("$root\dashboard\server.mjs") -WorkingDirectory "$root\dashboard" `
            -WindowStyle Hidden -RedirectStandardOutput "$logs\dashboard.out.log" -RedirectStandardError "$logs\dashboard.err.log"
    } catch { Log "failed to start dashboard: $_" }
}

function Ensure-Obs {
    if (Get-Process -Name obs64 -ErrorAction SilentlyContinue) { return }
    Log "starting OBS (profile '$($settings.obsProfile)', collection '$($settings.obsCollection)')"
    # After a crash OBS leaves a run_* marker in .sentinel and, on the next start, waits on a "Crash Detected -
    # run in Safe Mode?" dialog that would block an unattended restart. OBS isn't running here, so any marker is stale.
    Get-ChildItem "$env:APPDATA\obs-studio\.sentinel" -Filter 'run_*' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath "$obsDir\obs64.exe" -WorkingDirectory $obsDir -ArgumentList @(
        '--profile', "`"$($settings.obsProfile)`"", '--collection', "`"$($settings.obsCollection)`"",
        '--scene', '"IRL BRB"', '--disable-missing-files-check', '--minimize-to-tray')
    Start-Sleep -Seconds 15
}

Log 'watchdog started'
$nextTokenCheck = Get-Date
while ($true) {
  try {
    if ((Get-Date) -ge $nextTokenCheck) {
        $nextTokenCheck = (Get-Date).AddHours(1)
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$root\scripts\Refresh-TwitchToken.ps1`""
    }
    if (-not (Test-Path $pauseFlag)) {
        Ensure-Obs
        Rotate-MediamtxLog
        Ensure 'mediamtx' "$root\mediamtx\mediamtx.exe" @("$root\mediamtx\mediamtx.yml") "$root\mediamtx"
        Ensure 'go-irl' "$root\go-irl\go-irl.exe" @('-cli', '-mode=standalone', '-srtla-port=5000', '-udp-port=5002',
            '-ws-port=8888', '-bs-port=9999', "-passphrase=$($secrets.goirlPassphrase)") "$root\go-irl"
        Ensure 'noalbs' "$root\noalbs\noalbs.exe" $null "$root\noalbs"
    }
    # The dashboard (and Caddy, which serves it over HTTPS) stays up even while paused, so you can see that it is paused.
    Ensure-Dashboard
    if (Test-Path "$root\caddy\Caddyfile") {
        Ensure 'caddy' "$root\caddy\caddy.exe" @('run', '--config', "$root\caddy\Caddyfile", '--adapter', 'caddyfile') "$root\caddy"
    }
  } catch {
    # Never let one bad check stop the watchdog; log it and keep going.
    Log "watchdog error: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
  }
    Start-Sleep -Seconds 10
}
