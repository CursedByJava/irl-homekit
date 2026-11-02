# Sets the username and password for the remote dashboard and Studio (both use the same login).
#   Change it:        Start menu > "IRL Homekit - Change login" (or run this script)
#   Non-interactive:  Set-DashboardLogin.ps1 -Username me -Password '...'
# Changing the password signs out every device. The dashboard picks up the change by itself; no restart needed.
param(
    [string] $Username = '',
    [string] $Password = '',
    [string] $InstallDir = (Split-Path $PSScriptRoot -Parent),
    # Only ask for the login and return it (used by the installer before anything is written).
    [switch] $AskOnly,
    [switch] $Quiet
)
$ErrorActionPreference = 'Stop'
$MinLength = 10

function New-Password {
    $c = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray(); $b = New-Object byte[] 16
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); -join ($b | ForEach-Object { $c[$_ % $c.Length] })
}
function Read-Hidden($prompt) { [Net.NetworkCredential]::new('', (Read-Host $prompt -AsSecureString)).Password }

function Read-Login($currentUser) {
    $u = Read-Host "Username [$currentUser]"
    $u = if ($u.Trim()) { $u.Trim() } else { $currentUser }
    while ($true) {
        $p = Read-Hidden "Password (at least $MinLength characters, Enter = make a strong one for me)"
        if (-not $p) { return [pscustomobject]@{ Username = $u; Password = (New-Password); Generated = $true } }
        if ($p.Length -lt $MinLength) { Write-Host "    Too short: use at least $MinLength characters." -ForegroundColor Yellow; continue }
        if ((Read-Hidden 'Type it again') -ne $p) { Write-Host "    The two passwords don't match. Try again." -ForegroundColor Yellow; continue }
        return [pscustomobject]@{ Username = $u; Password = $p; Generated = $false }
    }
}

$secretsFile = Join-Path $InstallDir 'secrets.json'
$s = if (Test-Path $secretsFile) { Get-Content $secretsFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { [pscustomobject]@{} }

if ($AskOnly) { return Read-Login $(if ($Username) { $Username } else { 'admin' }) }

$generated = $false
if (-not $Username -and -not $Password) {
    Write-Host "`nIRL Homekit - change the dashboard login" -ForegroundColor Cyan
    Write-Host 'This login opens both the dashboard and Studio. Changing the password signs out every device.'
    $l = Read-Login $(if ($s.dashboardUser) { $s.dashboardUser } else { 'admin' })
    $Username = $l.Username; $Password = $l.Password; $generated = $l.Generated
}
if (-not $Username) { $Username = $s.dashboardUser }
if (-not $Password) { $Password = $s.dashboardPassword }
if (-not $Username -or -not $Password) { throw 'Give both -Username and -Password.' }
if ($Username -match '\s') { throw 'The username cannot contain spaces.' }

# 1. secrets.json keeps the readable copy (the installer and your setup guide read it from there).
$s | Add-Member -Force dashboardUser $Username
$s | Add-Member -Force dashboardPassword $Password
[IO.File]::WriteAllText($secretsFile, ($s | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding $false))

# 2. The dashboard only stores a scrypt hash. Keep the old hash when nothing changed, so re-installs don't sign you out.
$node = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
if (-not $node) { throw 'Node.js not found. Install it with:  winget install OpenJS.NodeJS.LTS' }
$env:IRLHK_PW = $Password
try {
    $result = & $node -e @'
const c = require('crypto'), fs = require('fs'), [file, user] = process.argv.slice(1), pw = process.env.IRLHK_PW;
let cfg = { port: 8090 }; try { cfg = JSON.parse(fs.readFileSync(file, 'utf8')); } catch {}
if (cfg.username === user && cfg.passwordHash) {
  const [salt, hash] = cfg.passwordHash.split(':');
  if (c.scryptSync(pw, Buffer.from(salt, 'hex'), 64).equals(Buffer.from(hash, 'hex'))) { console.log('unchanged'); process.exit(0); }
}
const salt = c.randomBytes(16);
cfg.username = user; cfg.passwordHash = salt.toString('hex') + ':' + c.scryptSync(pw, salt, 64).toString('hex');
fs.writeFileSync(file, JSON.stringify(cfg, null, 2)); console.log('changed');
'@ (Join-Path $InstallDir 'dashboard\config.json') $Username
} finally { $env:IRLHK_PW = $null }
if ($LASTEXITCODE -ne 0) { throw 'Could not save the new login.' }

# 3. Keep the personal setup guide in sync.
$guide = Join-Path $InstallDir 'PHONE-SETUP.md'
if (Test-Path $guide) {
    $g = [IO.File]::ReadAllText($guide)
    $g = $g -replace '(?m)^\| Username \| `[^`]*` \|', ("| Username | ``" + $Username.Replace('$', '$$') + "`` |")
    $g = $g -replace '(?m)^\| Password \| `[^`]*` \|', ("| Password | ``" + $Password.Replace('$', '$$') + "`` |")
    [IO.File]::WriteAllText($guide, $g, (New-Object Text.UTF8Encoding $false))
}

if ($Quiet) { return }
if ($result -eq 'unchanged') { Write-Host "`nLogin unchanged (user $Username)." -ForegroundColor Green; return }
Write-Host "`nLogin saved. Every device has been signed out." -ForegroundColor Green
Write-Host "    Username  $Username"
Write-Host "    Password  $(if ($generated) { $Password } else { '(the one you just typed)' })"
if ($generated) { Write-Host '    Save that password in your phone''s password manager. It''s also in PHONE-SETUP.md.' -ForegroundColor Yellow }
