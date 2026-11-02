# Your IRL Homekit setup

Keep this file private: it contains your stream passwords (also stored in `{{INSTALL_DIR}}\secrets.json`).

## 1. Finish the PC side

1. **Router port forwarding** → forward to this PC (`{{LAN_IP}}`). See `docs/ROUTER.md` in the IRL Homekit repo for router-by-router steps.

   | Protocol | Port | What |
   |---|---|---|
   | UDP | 5000 | Bonded phone stream (go-irl / SRTLA) |
   | UDP | 8890 | Backup phone stream (SRT) |
   | TCP | 1935 | Backup phone stream (RTMP), optional |
   | TCP | 443 + 80 | Remote dashboard (only if you set a domain) |

   Also give this PC a **DHCP reservation** so it keeps `{{LAN_IP}}`.
2. **Automatic sign-in** (optional) so IRL Homekit comes back by itself after a reboot or power cut (it opens when you sign in): Win+R → `netplwiz` → untick
   *"Users must enter a user name and password"* (if the box is missing, first turn off *Settings → Accounts →
   Sign-in options → "only allow Windows Hello sign-in"*).
3. **OBS stream key**: open **IRL Homekit** (desktop icon) → in its OBS, *Settings → Stream*: check your Twitch key is there.
4. **Kick / YouTube (optional, free multistream)**: in the IRL Homekit OBS → *Docks → Multiple output* → edit **Kick** / **YouTube**,
   paste the server + stream key, tick **enabled**. Leave *sync start* off: IRL Homekit starts and stops them with the
   main stream, following the dashboard's **Stream to** switches (switch any platform off to skip it).
5. **Twitch chat commands (optional)**: https://twitchtokengenerator.com → enable only `chat:read` + `chat:edit` →
   *Generate Token* → authorize → solve the CAPTCHA → Start menu →
   **"IRL Homekit - Twitch chat token"** and paste the Access + Refresh token.
6. **Self-test**: `powershell -ExecutionPolicy Bypass -File {{INSTALL_DIR}}\tools\Test-IRLHomekit.ps1`

## 2. Phone — IRL Pro (Android)

### Android settings first
- *Settings → Apps → IRL Pro → Battery* → **Unrestricted**; allow background data.
- *Developer options* → **Mobile data always active = ON** (otherwise Android drops 5G while on Wi-Fi and bonding
  can't use both). Enable Developer options by tapping *Build number* 7 times.
- Samsung: *Connections → Wi-Fi → Intelligent Wi-Fi* → **Switch to mobile data = OFF**.

### Connection 1 — Bonded (main)
| Field | Value |
|---|---|
| Protocol | **SRTLA** |
| Server | `srtla://{{PHONE_HOST}}:5000` |
| Passphrase | `{{GOIRL_PASSPHRASE}}` |
| Stream ID | (empty) |
| Latency | `2000` ms (3000–4000 in crowded areas) |
| Bonding | **ON** — Mobile data + Wi-Fi (+ USB/hotspot) |

No separate passphrase field in your app version? Use `srtla://{{PHONE_HOST}}:5000?passphrase={{GOIRL_PASSPHRASE}}`.

### Connection 2 — Backup (plain SRT, no bonding)
| Field | Value |
|---|---|
| Protocol | **SRT** |
| Server | `srt://{{PHONE_HOST}}:8890` |
| Stream ID | `publish:live:{{MEDIAMTX_USER}}:{{MEDIAMTX_PASS}}` |
| Latency | `2000` ms |

Last resort RTMP: `rtmp://{{PHONE_HOST}}:1935/live?user={{MEDIAMTX_USER}}&pass={{MEDIAMTX_PASS}}`

### Video / audio
- **1920×1080, 60 fps** (drop to 30 if the phone gets hot or signal is weak — OBS still outputs 60)
- **H.265 / HEVC**, adaptive bitrate **ON**, max **8000 kbps**, min **500 kbps**, keyframe **1 s**
- Audio **AAC 48 kHz, 128–160 kbps**

## 3. Going live

1. Start streaming in IRL Pro → OBS on the PC switches from **IRL BRB** to **IRL LIVE** within seconds.
2. Start the OBS stream from the **dashboard** (Start stream) or type **`!start`** in Twitch chat.
3. End with **End stream** / **`!stop`**. If you just stop IRL Pro, viewers see BRB and the stream ends by
   itself after 20 minutes (`offlineTimeout` in `{{INSTALL_DIR}}\noalbs\config.json`).

Signal rules: under **1000 kbps** → *IRL LOW* (banner), under **300 kbps** or disconnected → *IRL BRB*.

## 4. Remote dashboard

| | |
|---|---|
| Dashboard | **{{DASHBOARD_URL}}** |
| Studio | **{{STUDIO_URL}}** |
| Username | `{{DASHBOARD_USER}}` |
| Password | `{{DASHBOARD_PASS}}` |

- One login for both pages. You stay signed in for 30 days on each device; after 5 wrong passwords sign-in
  locks for 15 minutes.
- **Change your username or password:** Start menu → **IRL Homekit - Change login**. It
  signs out every device and updates this file.
- Tip: open the dashboard on your phone and *Add to Home Screen* for an app icon. Let your phone's password
  manager save the login.
- Dashboard: phone signal per bonded link, live preview, uptime/bitrate/dropped frames, start/stop, scenes, mute,
  reload feed/overlays, restart services. Studio: combined chat, viewers, title and category on every platform.

## 5. Everyday

**Open / close:** the **IRL Homekit** desktop icon opens it; closing its OBS window stops everything. It opens by itself
when you sign in (turn off on the dashboard: Home PC → Start with Windows). Start menu folder *IRL Homekit*:
**Status**, **Update scenes**, **Import from OBS**, **Twitch chat token**, **Change login**, **Check for updates**,
**Save diagnostics** (for bug reports), **Uninstall**. IRL Homekit also offers updates by itself when you open it. Logs: `{{INSTALL_DIR}}\logs`. Your public IP today: `{{PUBLIC_IP}}`. If it changes, the Status shortcut tells you what to update (nothing, if you use
a DuckDNS name with its token, see docs/DOMAIN.md in the repo).
