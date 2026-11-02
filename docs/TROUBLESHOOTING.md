# Troubleshooting

Start with the **IRL Homekit - Status** desktop shortcut and the dashboard's *Home PC* card. Logs are in
`C:\IRLHomekit\logs`.

| Symptom | Likely cause | Fix |
|---|---|---|
| Phone says connected, OBS stays on BRB | Router not forwarding UDP 5000, or wrong passphrase | Check `ROUTER.md`; compare the passphrase in IRL Pro with `PHONE-SETUP.md`; look in `logs\go-irl.err.log` for `Registered` lines |
| IRL Pro can't connect at all | Public IP changed, or Windows Firewall blocking | Status shortcut shows your current IP; re-run `install.ps1` (as admin) to recreate firewall rules |
| Works on Wi-Fi at home, not on mobile data | Testing via your own Wi-Fi doesn't prove forwarding | Test with Wi-Fi off; check the router rules |
| Video frozen but stats look fine | OBS media source stuck | Dashboard → *Quick fixes → Reload feed* |
| Never switches to LIVE, NOALBS log silent | OBS WebSocket off or wrong password | OBS → *Tools → WebSocket Server Settings*: enabled, port 4455, password = `obsWebsocketPassword` in `secrets.json` |
| Dashboard shows "OBS offline" | OBS closed or crashed | The watchdog restarts it within ~30 s; if it keeps crashing, check third-party OBS plugins |
| `https://your-domain` doesn't load | DNS not pointing at you, or ports 80/443 not forwarded | `nslookup your-domain` must show your public IP; `logs\caddy.log` shows certificate errors; setup steps in [DOMAIN.md](DOMAIN.md) |
| Chat commands don't answer | No bot token, or token revoked | Run the *Twitch chat token* shortcut again |
| Kick/YouTube don't start | Target disabled or key missing | OBS → *Multiple output* dock → edit target → key + *enabled* |
| PC slept / rebooted and nothing came back | Auto sign-in off | `netplwiz` → untick password requirement |

## Self-test
```
powershell -ExecutionPolicy Bypass -File C:\IRLHomekit\tools\Test-IRLHomekit.ps1
```
Sends fake phone streams (backup, low bitrate, bonded SRTLA) into the PC and checks OBS switches scenes. It never
starts your real stream.

## Turning it off for a desktop stream
*IRL Homekit - Pause* stops the receivers and keeps the watchdog from reopening OBS, so you can switch OBS to your
normal profile. *IRL Homekit - Resume* turns it back on.
