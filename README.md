# IRL Homekit

**Self-hosted IRL streaming from your own Windows PC: a free alternative to IRL Toolkit / cloud OBS.**

Your phone (IRL Pro, Moblin, BELABOX) sends a bonded 5G + Wi-Fi stream to the PC at home. OBS there adds your
overlays, automatically drops to a "low signal" or "be right back" scene when your connection struggles, and sends
1080p60 to Twitch, Kick and YouTube at the same time. A mobile web dashboard lets you watch your signal and
control everything from the street.

```
Phone (IRL Pro, bonded 5G + Wi-Fi)
   │  SRTLA → UDP 5000          backup: SRT → UDP 8890 / RTMP → TCP 1935
   ▼
Home PC ── go-irl (bonded receiver) ──┐
        ── MediaMTX (backup receiver) ┤→ OBS "IRL Homekit"  ── Twitch
        ── NOALBS (auto scene switch) ┘   LIVE / LOW / BRB   ── Kick     (obs-multi-rtmp)
        ── Dashboard + Caddy (HTTPS) ← you, on your phone    ── YouTube  (obs-multi-rtmp)
```

## What you get

| | IRL Toolkit-style feature | How |
|---|---|---|
| ✅ | Bonded cellular + Wi-Fi ingest (SRTLA) | [go-irl](https://github.com/e04/go-irl) |
| ✅ | Backup SRT / RTMP ingest | [MediaMTX](https://github.com/bluenviron/mediamtx), password protected |
| ✅ | Auto LIVE / LOW / BRB scenes, `!bitrate` `!start` `!stop` chat commands | [NOALBS](https://github.com/NOALBS/nginx-obs-automatic-low-bitrate-switching) |
| ✅ | Multistream Twitch + Kick + YouTube without Restream | [obs-multi-rtmp](https://github.com/sorayuki/obs-multi-rtmp) |
| ✅ | Remote control page with live signal, preview, start/stop, scenes, mute | `dashboard/` (Node, no dependencies) |
| ✅ | Studio page: combined Twitch/Kick/YouTube chat, viewers, title & category everywhere | `dashboard/` + official platform APIs |
| ✅ | Free HTTPS on your own domain | [Caddy](https://caddyserver.com) + Let's Encrypt |
| ✅ | Runs 24/7, restarts anything that crashes, survives reboots | watchdog + logon task |

Cost: $0/month. Uses your home upload (about 8 Mbps per platform).

## Requirements

- Windows 10/11 PC that can stay on, with a decent GPU (NVIDIA/AMD encoder recommended)
- [OBS Studio](https://obsproject.com) 30 or newer
- [Node.js](https://nodejs.org) 22 or newer: `winget install OpenJS.NodeJS.LTS`
- A home connection with a **public IPv4** you can port-forward (most fiber/cable; not CGNAT, see [ROUTER.md](docs/ROUTER.md))
- Optional: a domain or subdomain for the dashboard (any DNS provider, one A record)
- Optional for the self-test: ffmpeg, `winget install Gyan.FFmpeg`

## Install

1. Download this repo (green **Code** button → *Download ZIP*) and unzip it, or `git clone` it.
2. **Close OBS.**
3. Open PowerShell **as administrator**, `cd` into the folder and run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```
   It asks for your Twitch channel, which existing OBS scene collection/profile to copy (optional), which browser
   sources (chat, alerts) to show on the IRL scenes, and a dashboard domain (optional).
4. Open `C:\IRLHomekit\PHONE-SETUP.md`. It has **your** IRL Pro settings, passwords and the last manual steps:
   - Router port forwarding ([ROUTER.md](docs/ROUTER.md))
   - Windows auto sign-in
   - Twitch stream key, plus optional Kick/YouTube keys and chat-command token
5. Run the self-test: `powershell -ExecutionPolicy Bypass -File C:\IRLHomekit\tools\Test-IRLHomekit.ps1`
6. Go live from your phone with Wi-Fi off to prove it works from outside.

Installer options (all optional): `-InstallDir`, `-TwitchChannel`, `-Domain`, `-BaseCollection`, `-BaseProfile`,
`-OverlaySources "Chat,Alerts"`, `-BrbBackground "<media source>"`, `-ObsName`, `-ObsDir`, `-NonInteractive`.
Re-running is safe and keeps your passwords.

## Dashboard

`https://your-domain` (or `http://localhost:8090` on the PC). Sign in with the user and password from
`PHONE-SETUP.md`. Mobile-first and readable outdoors:

- **Phone signal:** bitrate, latency, packet loss, each bonded link, which input is active, in plain words ("Weak: viewers see the LOW SIGNAL banner")
- **Stream:** live preview, uptime, outgoing bitrate, dropped frames, live outputs, Start/End with confirmation,
  one-tap 60 / 30 fps switch (while offline)
- **Scenes:** one tap; auto-switched scenes are labelled
- **Audio:** mute the phone mic remotely
- **Quick fixes:** reload a frozen feed, reload chat/alerts, recording. The phone feed is also rebuilt automatically
  every time the phone reconnects, so a codec or resolution change on the phone never leaves OBS showing garbage
- **Home PC:** health of each service with restart buttons
- **Auto-switch history**

Security: HTTPS only, scrypt-hashed password, 30-day HttpOnly/SameSite=Strict session cookie, 15-minute lockout
after 5 failed sign-ins, strict CSP, API bound to localhost behind Caddy.

## Studio: your channels in one place

`https://studio.your-domain` (same login) is the control room for your channels:

- **Live status and viewers** on Twitch, Kick and YouTube, plus a combined total
- **Combined chat** from all three, colour-coded, with sending to any or all platforms
- **Title and category** updated on every connected platform at once
- **Links** to platform-only settings, e.g. Twitch's go-live notification

Connecting Kick and YouTube uses your own free developer app on each platform. See
[docs/PLATFORMS.md](docs/PLATFORMS.md).

## How it works

| Piece | Port | Notes |
|---|---|---|
| go-irl | UDP 5000 (public) → UDP 5002 (local, OBS) | Encrypted with a generated passphrase |
| MediaMTX | UDP 8890 SRT, TCP 1935 RTMP (public); API 127.0.0.1:9997 | Publishing needs user/password; RTSP/HLS/WebRTC off |
| OBS WebSocket | 4455 (not forwarded) | NOALBS + dashboard control OBS through it |
| NOALBS | — | Reads go-irl/MediaMTX stats; LOW < 1000 kbps, BRB < 300 kbps; ends stream after 20 min on BRB |
| Dashboard | 127.0.0.1:8090 | `dashboard/server.mjs`, Node built-ins only |
| Caddy | TCP 443/80 (public) | Automatic Let's Encrypt certificate |
| Watchdog | — | `scripts/Start-IRLHomekit.ps1`, started at sign-in by the *IRL Homekit* task |

Files after install (`C:\IRLHomekit`): `secrets.json` (generated passwords, **never share**), `settings.json`,
`PHONE-SETUP.md`, `logs\`, plus each tool's folder. Your own OBS profiles and collections are never modified; the
installer creates new ones named *IRL Homekit*.

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Credits

Built on great open-source projects: go-irl (AGPL-3.0), MediaMTX (MIT), NOALBS (MIT), obs-multi-rtmp (GPL-2.0),
Caddy (Apache-2.0), OBS Studio (GPL-2.0). The installer downloads their official releases and verifies their
checksums; this repo doesn't redistribute their binaries. See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## License

MIT, see [LICENSE](LICENSE). Applies to the scripts and dashboard in this repo only.
