# Shows where your dashboard and Studio pages are, with Copy and Open buttons, so you can get them onto your phone.
# Start menu > "IRL Homekit - Dashboard address".
param([string] $InstallDir = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$settings = Get-Content "$InstallDir\settings.json" -Raw | ConvertFrom-Json
$cfg = try { Get-Content "$InstallDir\dashboard\config.json" -Raw | ConvertFrom-Json } catch { $null }
$domain = "$($settings.domain)".Trim()
$dash = if ($domain) { "https://$domain" } else { 'http://localhost:8090' }
$studio = if ($settings.studioDomain) { "https://$($settings.studioDomain)" } else { "$dash/studio" }

$f = New-Object Windows.Forms.Form
$f.Text = 'IRL Homekit - Dashboard address'; $f.StartPosition = 'CenterScreen'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false
$f.ClientSize = New-Object Drawing.Size 620, 330; $f.BackColor = [Drawing.Color]::FromArgb(28, 28, 30); $f.ForeColor = [Drawing.Color]::White
$f.Font = New-Object Drawing.Font 'Segoe UI', 10
$icon = "$InstallDir\dashboard\public\icon.ico"; if (Test-Path $icon) { $f.Icon = New-Object Drawing.Icon $icon }
function Label($text, $y, $size = 10, $bold = $false, $color = $null) {
    $l = New-Object Windows.Forms.Label; $l.Text = $text; $l.Location = New-Object Drawing.Point 24, $y; $l.AutoSize = $true; $l.MaximumSize = New-Object Drawing.Size 572, 0
    $l.Font = New-Object Drawing.Font 'Segoe UI', $size, $(if ($bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular })
    if ($color) { $l.ForeColor = $color }; $f.Controls.Add($l); $l
}
function Button($text, $x, $y, $onClick) {
    $b = New-Object Windows.Forms.Button; $b.Text = $text; $b.Location = New-Object Drawing.Point $x, $y; $b.Size = New-Object Drawing.Size 110, 34
    $b.FlatStyle = 'Flat'; $b.BackColor = [Drawing.Color]::FromArgb(58, 58, 60); $b.ForeColor = [Drawing.Color]::White; $b.Add_Click($onClick); $f.Controls.Add($b); $b
}
$muted = [Drawing.Color]::FromArgb(170, 170, 175)

$null = Label 'Your dashboard' 18 10 $true $muted
$addr = Label $dash 40 20 $true
$null = Button 'Copy' 24 86 { [Windows.Forms.Clipboard]::SetText($dash); $this.Text = 'Copied' }
$null = Button 'Open' 142 86 { Start-Process $dash }
$null = Label "Studio (chat, title, viewers): $studio" 132 10 $false $muted
$login = if ($cfg.username) { "Sign in as $($cfg.username) with your dashboard password (forgot it? Start menu > IRL Homekit - Change login)." } else { '' }
if ($domain) {
    $null = Label ("On your phone: open Chrome (or Safari), tap the address bar at the top, type $dash and press Go. Type it into the address bar, not a Google search. " +
        "Then use the browser's menu > Add to Home screen, so it's one tap next time. $login") 168 10
} else {
    $null = Label ("This address only works on this PC. To use the dashboard on your phone, from anywhere, set up the remote dashboard " +
        "(free, about 5 minutes): it gives you an address like https://yourname.duckdns.org. $login") 168 10 $false ([Drawing.Color]::FromArgb(255, 214, 10))
    $null = Button 'Set it up' 24 270 { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$InstallDir\scripts\Setup-RemoteDashboard.ps1`""; $f.Close() }
}
$close = Button 'Close' 486 280 { $f.Close() }; $f.AcceptButton = $close; $f.CancelButton = $close
$f.Add_Shown({ $close.Focus() })   # a stray Enter closes the window instead of pressing Copy
[void]$f.ShowDialog()
