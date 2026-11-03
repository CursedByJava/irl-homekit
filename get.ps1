# IRL Homekit one-line install. Open PowerShell (or Terminal) and paste:
#
#     irm https://raw.githubusercontent.com/CursedByJava/irl-homekit/main/get.ps1 | iex
#
# It downloads the newest IRL Homekit release from GitHub and starts its installer, the same one Setup.exe and
# "Install IRL Homekit.cmd" run: Windows asks for administrator permission once, then the installer asks its
# questions. Nothing is installed before that. Running it again updates IRL Homekit.
# Handy when Windows Smart App Control blocks Setup.exe: this way there's no downloaded program for it to block.
& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'   # Windows PowerShell's progress bar slows downloads down a lot
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $repo = 'CursedByJava/irl-homekit'
    $headers = @{ 'User-Agent' = 'IRL-Homekit-get' }
    try {
        Write-Host 'IRL Homekit: looking for the newest release...' -ForegroundColor Magenta
        # Newest stable release; newest beta while there's no stable one yet.
        $rels = Invoke-RestMethod "https://api.github.com/repos/$repo/releases?per_page=20" -Headers $headers -TimeoutSec 20
        $all = @($rels | Where-Object { -not $_.draft })
        $rel = @($all | Where-Object { -not $_.prerelease }) + $all | Select-Object -First 1
        if (-not $rel) { throw "No releases found at https://github.com/$repo/releases." }
        $work = Join-Path $env:TEMP "irl-homekit-$($rel.tag_name)"
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
        New-Item -ItemType Directory -Path $work | Out-Null
        Write-Host "Downloading IRL Homekit $($rel.tag_name)..."
        Invoke-WebRequest $rel.zipball_url -OutFile (Join-Path $work 'release.zip') -UseBasicParsing -Headers $headers
        Expand-Archive (Join-Path $work 'release.zip') (Join-Path $work 'src') -Force
        $cmd = Get-ChildItem (Join-Path $work 'src') -Recurse -Filter 'Install IRL Homekit.cmd' | Select-Object -First 1
        if (-not $cmd) { throw 'The download does not contain the installer.' }
        Write-Host 'Starting the installer. Click Yes when Windows asks for permission; it opens in a new window.' -ForegroundColor Cyan
        Start-Process -FilePath $cmd.FullName -Verb RunAs
    } catch {
        if ("$_" -match 'canceled by the user') { Write-Host 'Nothing was installed: Windows permission was declined. Paste the command again to retry.' -ForegroundColor Yellow }
        else { Write-Host "IRL Homekit couldn't be downloaded: $($_.Exception.Message)" -ForegroundColor Red; Write-Host "Other ways to install: https://github.com/$repo#install" }
    }
}
