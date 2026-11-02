# Saves your Kick developer app and Google (YouTube) OAuth client into secrets.json, then restarts the dashboard.
# See docs/PLATFORMS.md for how to create them. Leave a prompt empty to keep what's already saved.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$file = "$root\secrets.json"
$s = Get-Content $file -Raw | ConvertFrom-Json
$fields = [ordered]@{
    kickClientId = 'Kick app Client ID'; kickClientSecret = 'Kick app Client Secret'
    youtubeClientId = 'Google OAuth Client ID (ends in .apps.googleusercontent.com)'; youtubeClientSecret = 'Google OAuth Client secret (starts with GOCSPX-)'
}
foreach ($k in $fields.Keys) {
    $v = (Read-Host $fields[$k]).Trim()
    if ($v) { $s | Add-Member -Force $k $v }
}
# Check the values with each platform before saving, so a typo shows up now instead of at sign-in.
if ($s.kickClientId -and $s.kickClientSecret) {
    try { $null = Invoke-RestMethod 'https://id.kick.com/oauth/token' -Method Post -ContentType 'application/x-www-form-urlencoded' `
            -Body @{ grant_type = 'client_credentials'; client_id = $s.kickClientId; client_secret = $s.kickClientSecret }; Write-Host 'Kick app: OK' -ForegroundColor Green }
    catch { Write-Host 'Kick app: Kick rejected the Client ID/Secret. Copy them again from kick.com > Settings > Developer.' -ForegroundColor Red }
}
if ($s.youtubeClientId -and $s.youtubeClientSecret) {
    $body = "code=check&client_id=$($s.youtubeClientId)&client_secret=$([uri]::EscapeDataString($s.youtubeClientSecret))&redirect_uri=https%3A%2F%2Fexample.com&grant_type=authorization_code"
    try { Invoke-WebRequest 'https://oauth2.googleapis.com/token' -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing | Out-Null }
    catch {
        $msg = if ($_.Exception.Response) { (New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())).ReadToEnd() } else { '' }
        if ($msg -match 'invalid_client') { Write-Host 'Google client: Google rejected the Client ID/secret. Check for l/I mix-ups when copying.' -ForegroundColor Red }
        else { Write-Host 'Google client: OK' -ForegroundColor Green }
    }
}
$s | ConvertTo-Json | Set-Content -Encoding UTF8 $file
Get-NetTCPConnection -LocalPort 8090 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }
Write-Host 'Saved. The dashboard restarts in ~10 seconds; then open Studio and tap Connect next to Kick / YouTube.'
