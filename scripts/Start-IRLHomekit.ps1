# IRL Homekit app. The "IRL Homekit" shortcut (Start menu / desktop) runs this as administrator through the
# "IRL Homekit" Windows task; with "Start with Windows" on, the "IRL Homekit (sign-in)" task runs it with
# -Background (OBS starts minimized to the tray). See Install-Shortcuts.ps1.
#
# It opens IRL Homekit's own copy of OBS (separate from your normal OBS) and keeps MediaMTX, go-irl, NOALBS, the
# dashboard and Caddy running, restarting anything that crashes. When you close the IRL Homekit OBS window,
# everything stops. Opening the shortcut again while it's running just brings the OBS window back.
param([switch] $Background)
$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
$logs = "$root\logs"
$secrets = Get-Content "$root\secrets.json" -Raw | ConvertFrom-Json
$settings = Get-Content "$root\settings.json" -Raw | ConvertFrom-Json
$obsDir = $settings.obsDir
$obsExe = Join-Path $obsDir 'obs64.exe'
$node = @("$root\node\node.exe", (Get-Command node.exe -ErrorAction SilentlyContinue).Source, "$env:ProgramFiles\nodejs\node.exe") |
    Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1   # IRL Homekit's own copy first (see install.ps1)

Add-Type -Namespace IRLHK -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
public delegate bool EnumProc(IntPtr h, IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SetWindowText(IntPtr h, string s);
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr LoadImage(IntPtr inst, string name, int type, int cx, int cy, int flags);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct NOTIFYICONDATA {
    public int cbSize; public IntPtr hWnd; public int uID; public int uFlags; public int uCallbackMessage; public IntPtr hIcon;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szTip; public int dwState; public int dwStateMask;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szInfo; public int uVersion;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string szInfoTitle; public int dwInfoFlags; public Guid guidItem; public IntPtr hBalloonIcon; }
[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern bool Shell_NotifyIcon(int msg, ref NOTIFYICONDATA d);
'@

# Only IRL Homekit's own OBS counts; your normal OBS can run at the same time.
# A crashed OBS can stay listed after it has exited (stuck closing until the PC restarts); that one doesn't count.
function Get-IrlObs {
    Get-Process -Name obs64 -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -eq $obsExe -and -not $(try { $_.HasExited } catch { $false })
    } | Sort-Object StartTime -Descending
}

# The main OBS window (not a dock or helper window), even while it's hidden in the tray.
function Get-IrlObsWindow {
    $p = Get-IrlObs | Select-Object -First 1; if (-not $p) { return [IntPtr]::Zero }
    $script:found = [IntPtr]::Zero
    [IRLHK.Win]::EnumWindows({ param($h, $l)
        $wpid = 0; [void][IRLHK.Win]::GetWindowThreadProcessId($h, [ref]$wpid)
        if ($wpid -eq $p.Id -and $script:found -eq [IntPtr]::Zero) {
            $sb = New-Object System.Text.StringBuilder 256; [void][IRLHK.Win]::GetWindowText($h, $sb, 256)
            if ($sb.ToString() -like 'OBS *' -or $sb.ToString() -like 'IRL Homekit*') { $script:found = $h }
        }
        $true }, [IntPtr]::Zero) | Out-Null
    $script:found
}

function Show-IrlObs {
    $h = Get-IrlObsWindow
    # SW_SHOW brings it back from the tray, SW_RESTORE un-minimizes it.
    if ($h -ne [IntPtr]::Zero) { [void][IRLHK.Win]::ShowWindow($h, 5); [void][IRLHK.Win]::ShowWindow($h, 9); [void][IRLHK.Win]::SetForegroundWindow($h) }
}

# Our logo on the window (title bar, taskbar, Alt+Tab) and "IRL Homekit" as its name, so it's never mistaken for
# your regular OBS. OBS resets the title when you switch profile or scene collection, so this is re-applied.
$iconFile = Join-Path $root 'dashboard\public\icon.ico'
$script:brandedFor = [IntPtr]::Zero
function Set-IrlBranding {
    $h = Get-IrlObsWindow; if ($h -eq [IntPtr]::Zero) { return }
    $sb = New-Object System.Text.StringBuilder 512; [void][IRLHK.Win]::GetWindowText($h, $sb, 512); $title = $sb.ToString()
    if ($title -like 'OBS *') {
        # "OBS 33.0.1 - Portable Mode - Profile: IRL Homekit - Scenes: IRL Homekit" -> "IRL Homekit - Profile: ... - Scenes: ..."
        [void][IRLHK.Win]::SetWindowText($h, ('IRL Homekit' + ($title -replace '^OBS [^-]*(- Portable Mode )?', ' ')).Replace('  ', ' '))
    }
    if ($script:brandedFor -ne $h -and (Test-Path $iconFile)) {
        $big = [IRLHK.Win]::LoadImage([IntPtr]::Zero, $iconFile, 1, 48, 48, 0x10)
        $small = [IRLHK.Win]::LoadImage([IntPtr]::Zero, $iconFile, 1, 16, 16, 0x10)
        [void][IRLHK.Win]::SendMessage($h, 0x80, [IntPtr]1, $big)     # WM_SETICON, ICON_BIG
        [void][IRLHK.Win]::SendMessage($h, 0x80, [IntPtr]0, $small)   # WM_SETICON, ICON_SMALL
        $script:brandedFor = $h
        $script:trayIcon = $small
    }
    # The tray icon too. It belongs to OBS's hidden tray window (Qt, icon id 0); OBS swaps it when you go live or
    # record, so it's set again every few seconds.
    $p = Get-IrlObs | Select-Object -First 1
    if ($p -and $script:trayIcon) {
        $script:trayWnd = [IntPtr]::Zero
        [IRLHK.Win]::EnumWindows({ param($w, $l)
            $wpid = 0; [void][IRLHK.Win]::GetWindowThreadProcessId($w, [ref]$wpid)
            if ($wpid -eq $p.Id) { $c = New-Object System.Text.StringBuilder 128; [void][IRLHK.Win]::GetClassName($w, $c, 128); if ($c.ToString() -like '*TrayIconMessageWindowClass') { $script:trayWnd = $w } }
            $true }, [IntPtr]::Zero) | Out-Null
        if ($script:trayWnd -ne [IntPtr]::Zero) {
            $d = New-Object IRLHK.Win+NOTIFYICONDATA
            $d.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($d); $d.hWnd = $script:trayWnd; $d.uID = 0
            $d.uFlags = 0x2 -bor 0x4; $d.hIcon = $script:trayIcon; $d.szTip = 'IRL Homekit'   # NIF_ICON | NIF_TIP
            [void][IRLHK.Win]::Shell_NotifyIcon(1, [ref]$d)                                   # NIM_MODIFY
        }
    }
}

# Only one copy at a time. A second launch (someone opened the shortcut again) just shows the OBS window.
$mutexName = 'Global\IRLHomekit-' + [BitConverter]::ToString([Security.Cryptography.SHA1]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLower()))).Replace('-', '').Substring(0, 12)
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0)) { if (-not $Background) { Show-IrlObs }; exit 0 }

function Log($msg) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path "$logs\watchdog.log" -Value $line
}

function Rotate($file) {
    if ((Test-Path $file) -and (Get-Item $file).Length -gt 20MB) { Move-Item $file "$file.old" -Force }
}

function Ensure($name, $exe, $argList, $workDir) {
    if (Get-Process -Name $name -ErrorAction SilentlyContinue) { return }
    if ($script:blockedUntil[$name] -and (Get-Date) -lt $script:blockedUntil[$name]) { return }   # blocked: retry once a minute
    Rotate "$logs\$name.out.log"; Rotate "$logs\$name.err.log"
    if (-not $script:blockedUntil[$name]) { Log "starting $name" }
    $p = @{ FilePath = $exe; WorkingDirectory = $workDir; WindowStyle = 'Hidden'
            RedirectStandardOutput = "$logs\$name.out.log"; RedirectStandardError = "$logs\$name.err.log" }
    if ($argList) { $p.ArgumentList = $argList }
    try {
        Start-Process @p
        if ($script:blockedUntil.ContainsKey($name)) { $script:blockedUntil.Remove($name); Save-Blocked; Log "$name is allowed now" }
    } catch {
        if ("$_" -match 'Application Control') {
            # Windows Smart App Control blocks unsigned programs. The dashboard explains how to allow them.
            if (-not $script:blockedUntil[$name]) { Log "Windows Smart App Control blocked $name" }
            $script:blockedUntil[$name] = (Get-Date).AddMinutes(1); Save-Blocked
        } else { Log "failed to start ${name}: $_" }
    }
}
$script:blockedUntil = @{}
function Save-Blocked { [IO.File]::WriteAllText("$logs\blocked.json", (ConvertTo-Json -Compress -InputObject @($script:blockedUntil.Keys))) }
Save-Blocked

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
function Get-DashboardPid { (Get-NetTCPConnection -LocalPort 8090 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess }
function Ensure-Dashboard {
    if (Get-DashboardPid) { return }
    Rotate "$logs\dashboard.out.log"; Rotate "$logs\dashboard.err.log"
    Log 'starting dashboard'
    try {
        Start-Process -FilePath $node -ArgumentList @("$root\dashboard\server.mjs") -WorkingDirectory "$root\dashboard" `
            -WindowStyle Hidden -RedirectStandardOutput "$logs\dashboard.out.log" -RedirectStandardError "$logs\dashboard.err.log"
    } catch { Log "failed to start dashboard: $_" }
}

# OBS exits with code 0 when you close it; anything else (a crash) gets it restarted.
$script:obsProc = $null
function Start-IrlObs([switch] $Minimized) {
    Log "starting IRL Homekit OBS (profile '$($settings.obsProfile)', collection '$($settings.obsCollection)')"
    $a = @('--portable', '--multi', '--profile', "`"$($settings.obsProfile)`"", '--collection', "`"$($settings.obsCollection)`"",
        '--scene', '"IRL BRB"', '--disable-missing-files-check')
    if ($Minimized) { $a += '--minimize-to-tray' }
    $script:obsProc = Start-Process -FilePath $obsExe -WorkingDirectory $obsDir -ArgumentList $a -PassThru
    $null = $script:obsProc.Handle   # keep a handle so the exit code can be read later
    Start-Sleep -Seconds 15
}
function Test-ObsCrashed {
    if (-not $script:obsProc) { return $false }   # OBS was already open when IRL Homekit started: treat as closed by you
    try { $code = $script:obsProc.ExitCode } catch { return $false }
    if ($code -ne 0) { Log ("IRL Homekit OBS exited with code 0x{0:X8}" -f $code) }
    $code -ne 0
}

function Stop-Everything {
    Log 'IRL Homekit OBS was closed; stopping everything'
    # Only this install's copies.
    Get-Process -Name noalbs, go-irl, mediamtx, caddy -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$root\*" } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    $d = Get-DashboardPid
    if ($d -and (Get-CimInstance Win32_Process -Filter "ProcessId=$d").CommandLine -like "*$root\dashboard\server.mjs*") {
        Stop-Process -Id $d -Force -ErrorAction SilentlyContinue
    }
}

# Free DuckDNS name (docs/DOMAIN.md): point it at this PC's current home IP. Logged only when the answer changes.
$lastDuck = ''
function Update-DuckDns {
    $r = try { Invoke-RestMethod "https://www.duckdns.org/update?domains=$($settings.duckdnsName)&token=$($secrets.duckdnsToken)" -TimeoutSec 10 } catch { "error: $($_.Exception.Message)" }
    if ($r -ne $script:lastDuck) { Log "DuckDNS update for $($settings.duckdnsName).duckdns.org: $r"; $script:lastDuck = $r }
}

Log $(if ($Background) { 'IRL Homekit started at sign-in' } else { 'IRL Homekit opened' })
if (-not (Get-IrlObs)) { Start-IrlObs -Minimized:$Background } elseif (-not $Background) { Show-IrlObs }
# Look for a newer IRL Homekit (at most once a day); if there is one, Windows shows an "Update now?" box.
$stamp = "$logs\update-check.txt"
if (-not (Test-Path $stamp) -or (Get-Item $stamp).LastWriteTime -lt (Get-Date).AddHours(-20)) {
    Set-Content $stamp (Get-Date -Format o)
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$root\scripts\Update-IRLHomekit.ps1`" -Prompt"
}
$nextTokenCheck = Get-Date
$nextDuck = Get-Date
$wsPort = if ($settings.obsWebsocketPort) { $settings.obsWebsocketPort } else { 4455 }
$noWsSince = $null
while ($true) {
  try {
    $irlObs = Get-IrlObs | Select-Object -First 1
    if (-not $irlObs) {
        if (Test-ObsCrashed) { Log 'IRL Homekit OBS crashed; restarting it'; Start-IrlObs -Minimized:$Background }
        else { Stop-Everything; break }
    } elseif (-not (Get-NetTCPConnection -LocalPort $wsPort -State Listen -ErrorAction SilentlyContinue)) {
        # Running but not answering: OBS crashed and is sitting on its crash window. Restart it after 45 seconds.
        if (-not $noWsSince) { $noWsSince = Get-Date }
        elseif ((Get-Date) - $noWsSince -gt [TimeSpan]::FromSeconds(45) -and (Get-Date) - $irlObs.StartTime -gt [TimeSpan]::FromSeconds(60)) {
            Log 'IRL Homekit OBS stopped responding (crashed with its window open); restarting it'
            $irlObs | Stop-Process -Force -ErrorAction SilentlyContinue; $noWsSince = $null
            Start-Sleep -Seconds 2; Start-IrlObs -Minimized:$Background
        }
    } else { $noWsSince = $null }
    Set-IrlBranding
    if ((Get-Date) -ge $nextTokenCheck) {
        $nextTokenCheck = (Get-Date).AddHours(1)
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$root\scripts\Refresh-TwitchToken.ps1`""
    }
    if ($settings.duckdnsName -and $secrets.duckdnsToken -and (Get-Date) -ge $nextDuck) {
        $nextDuck = (Get-Date).AddMinutes(5)
        Update-DuckDns
    }
    Rotate-MediamtxLog
    Ensure 'mediamtx' "$root\mediamtx\mediamtx.exe" @("$root\mediamtx\mediamtx.yml") "$root\mediamtx"
    Ensure 'go-irl' "$root\go-irl\go-irl.exe" @('-cli', '-mode=standalone', '-srtla-port=5000', '-udp-port=5002',
        '-ws-port=8888', '-bs-port=9999', "-passphrase=$($secrets.goirlPassphrase)") "$root\go-irl"
    Ensure 'noalbs' "$root\noalbs\noalbs.exe" $null "$root\noalbs"
    Ensure-Dashboard
    if (Test-Path "$root\caddy\Caddyfile") {
        Ensure 'caddy' "$root\caddy\caddy.exe" @('run', '--config', "$root\caddy\Caddyfile", '--adapter', 'caddyfile') "$root\caddy"
    }
  } catch {
    # Never let one bad check stop the watchdog; log it and keep going.
    Log "watchdog error: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
  }
    Start-Sleep -Seconds 5
}
Log 'IRL Homekit closed'
