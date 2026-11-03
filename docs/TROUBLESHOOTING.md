# Troubleshooting

Start with **IRL Homekit - Status** (Start menu) and the dashboard's *Home PC* card. Logs are in
`C:\IRLHomekit\logs`.

| Symptom | Likely cause | Fix |
|---|---|---|
| Phone says connected, OBS stays on BRB | Router not forwarding UDP 5000, or wrong passphrase | Check `ROUTER.md`; compare the passphrase in IRL Pro with `PHONE-SETUP.md`; look in `logs\go-irl.err.log` for `Registered` lines |
| IRL Pro can't connect at all | IRL Homekit closed, public IP changed, or Windows Firewall blocking | Make sure IRL Homekit is open; the Status shortcut shows your current IP; re-run `install.ps1` (as admin) to recreate firewall rules |
| Works on Wi-Fi at home, not on mobile data | Testing via your own Wi-Fi doesn't prove forwarding | Test with Wi-Fi off; check the router rules |
| Video frozen but stats look fine | OBS media source stuck | Dashboard → *Quick fixes → Reload feed* |
| Never switches to LIVE, NOALBS log silent | OBS WebSocket off or wrong password | OBS → *Tools → WebSocket Server Settings*: enabled, port 4455, password = `obsWebsocketPassword` in `secrets.json` |
| Dashboard shows "OBS offline" | OBS closed or crashed | The watchdog restarts it within ~30 s; if it keeps crashing, check third-party OBS plugins |
| `https://your-domain` doesn't load | DNS not pointing at you, or ports 80/443 not forwarded | `nslookup your-domain` must show your public IP; `logs\caddy.log` shows certificate errors; setup steps in [DOMAIN.md](DOMAIN.md) |
| Chat commands don't answer | No bot token, or token revoked | Run the *Connect Twitch* shortcut again |
| Kick/YouTube don't start | Target disabled or key missing | OBS → *Multiple output* dock → edit target → key + *enabled* |
| PC slept / rebooted and nothing came back | Auto sign-in off | `netplwiz` → untick password requirement |

## Self-test
```
powershell -ExecutionPolicy Bypass -File C:\IRLHomekit\tools\Test-IRLHomekit.ps1
```
Sends fake phone streams (backup, low bitrate, bonded SRTLA) into the PC and checks OBS switches scenes. It never
starts your real stream.

## Windows blocks the tools (Smart App Control)

**Symptom:** the installer warns "Windows Smart App Control is blocking …", or the dashboard says "Windows is
blocking go-irl, MediaMTX, NOALBS". The phone can't connect and scenes don't switch.

**Why:** *Smart App Control* (Windows 11) only lets programs run that are signed by a known publisher or that
Microsoft's cloud already trusts. go-irl, MediaMTX, NOALBS and Caddy are free, open-source tools without a paid
code-signing certificate, so on some PCs Windows refuses to start them. On other PCs (with Smart App Control on) they
run fine, because Windows decides per file.

**Fix:** Windows Security → **App & browser control** → **Smart App Control settings** → **Off**. IRL Homekit notices
within a minute and starts them by itself.

> Good to know: Windows doesn't let you turn Smart App Control back on without resetting Windows. Microsoft Defender
> antivirus keeps protecting the PC either way. If you'd rather keep it on, IRL Homekit can't run its phone receivers
> on that PC.

## Doing a desktop stream
Your regular OBS is separate from IRL Homekit's, so just use it. Close the IRL Homekit OBS window first so the two
don't compete for your graphics card (and so IRL Homekit's auto-switcher isn't running). Open IRL Homekit again
from the desktop icon afterwards.

## The IRL Homekit OBS
| Symptom | Fix |
|---|---|
| Dashboard offline after a restart | *Start with Windows* is off (dashboard: Home PC), or nobody signed in to Windows. Open IRL Homekit from the desktop icon, or set up auto sign-in (`PHONE-SETUP.md`). |
| Clicking the icon does nothing | It's already running, hidden in the tray: the click brings the window back. If not, open Task Scheduler and run the *IRL Homekit* task; if it's missing, run the installer again. |
| Can't drag files into the IRL Homekit OBS | It runs as administrator, and Windows blocks drag-and-drop into admin apps. Use **+** in Sources. |
| A plugin from your regular OBS is missing | Start menu → *IRL Homekit - Import from OBS*. Plugins only copy over when both OBS versions match; otherwise install the plugin into `C:\IRLHomekit\obs`. |
| Want the normal OBS look back | In the IRL Homekit OBS: *Settings → Appearance → Theme*. |
| Something's wrong after an import | The previous settings are in `C:\IRLHomekit\obs-config-backup\<date>`: close IRL Homekit and copy them back into `C:\IRLHomekit\obs\config\obs-studio`. |
