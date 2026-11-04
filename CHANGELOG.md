# Changelog

All notable changes to IRL Homekit. Versions follow [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`,
with `-beta.N` while the app is in beta. The format is based on [Keep a Changelog](https://keepachangelog.com).

> **IRL Homekit is in beta.** It works end to end, but expect rough edges, and things may change between betas.
> Please report problems on the [issues page](https://github.com/CursedByJava/irl-homekit/issues).

Each release is also published on the [Releases page](https://github.com/CursedByJava/irl-homekit/releases), which
is what the built-in update checker reads.

## [Unreleased]

## [1.0.0-beta.21] - 2026-11-03

### Added
- **Web server settings of your own survive updates.** Anything you put in `caddy\extra.caddy` is added to the web
  server's settings every time IRL Homekit writes them, so an extra site of your own stays. Handy when a second PC
  on your network can't have ports 80 and 443: the PC that has them can pass a name of your own through to it.

### Changed
- **Setup opens the QR code in your browser at the end of every install**, not only when it couldn't draw the code on
  the last page. The browser page makes a fresh code whenever the old one runs out, so there's always a working one
  to scan.

### Fixed
- **A second PC on the same network was told its router ports were ready when they weren't.** Only one PC can have
  ports 80 and 443, and a router that answers "already taken" doesn't say which PC has them. The check connected to
  your home's internet address and counted any answer as proof, so the other PC's answer looked like success: the
  install finished happily, no HTTPS certificate ever arrived, and the phone got a dead link. It now confirms the
  connection comes back to this PC, and says plainly when it can't, both in Setup's last page and in Status.
- **"Connect my phone" could hand out a QR code for a dead link.** On a PC the internet can't reach yet (the router
  hasn't let ports 80 and 443 through, your provider uses carrier-grade NAT, or another PC on the same network
  already has those ports), the page made a link to an address nothing answers on, and the phone simply failed to
  open it with no explanation. It now checks for the HTTPS certificate first and says what's in the way instead,
  the same as Setup's last page already did.

## [1.0.0-beta.20] - 2026-11-03

### Added
- **The dashboard on your phone with no account at all.** New first choice in Setup, the one-line install and
  *Set up remote dashboard*: "no account needed". Your dashboard gets your home's internet address, like
  `https://203.0.113.7`, with a real HTTPS certificate from Let's Encrypt (their certificates for IP addresses,
  new in 2026), set up and renewed by itself. No DuckDNS, no sign-in, no name to pick; the QR code puts it on your
  phone. If your internet provider changes your address, IRL Homekit notices within 5 minutes and moves the dashboard
  with it (scan a new QR code once). With a relay server, it uses the relay's address. DuckDNS and your own domain
  are still there for one address that never changes.
- **The QR code is right on Setup's last page.** Setup waits for IRL Homekit to start and for the dashboard's HTTPS
  certificate, then shows the code next to your login: scan it with your phone's camera and you're signed in, with
  *Open in IRL Pro* ready. A *New code* button makes another if it runs out (each works once, for 10 minutes). If the
  certificate can't be issued (the internet can't reach the PC), the page says so and what to run.

## [1.0.0-beta.19] - 2026-11-03

### Changed
- **The one-line install ends with the QR code too.** When it finishes (and the dashboard is set up for your phone),
  the Connect your phone page opens in your browser by itself, and a password it made for you is copied, like
  Setup.exe does.

## [1.0.0-beta.18] - 2026-11-03

### Fixed
- **No more grey box with black text at the top of the installer window** (the one-line install and Install IRL
  Homekit.cmd): that was Windows PowerShell's own download progress bar. It's off now, which also makes the
  downloads much faster; the installer's own lines say what it's downloading. Same for the updater window.

### Changed
- **Blocked by Windows? The one-line install is now right under the download button** (README and release notes),
  with a copy button: right-click Start, Terminal, paste, Enter. It runs the same installer, and Smart App Control has
  nothing to block. Setup.exe stays unsigned (signing costs money every year).

## [1.0.0-beta.17] - 2026-11-03

### Added
- **Connect your phone with a QR code.** Start menu → *IRL Homekit - Connect my phone* (also offered at the end of
  Setup, in the *Dashboard address* window, and as *Show QR code* on the dashboard) shows a code: point the phone's
  camera at it, and the dashboard opens on the phone already signed in, with *Open in IRL Pro* ready. No address or
  password to type. Each code works once, for 10 minutes, and can only be made on the PC itself or by someone signed
  in. (Needs the dashboard on your phone set up: a DuckDNS name or your own domain.)
- **Setup copies the password it made for you**, and its last page has *Copy password* and *Save login to a file*
  buttons (a text file on your desktop, or wherever you like).

### Changed
- **The phone guide that opens after Setup (PHONE-SETUP.md) is now four plain steps**: open the dashboard on your
  phone, tap *Open in IRL Pro*, three Android settings, go live. No tables or symbols, so it reads well in Notepad;
  the full settings for typing in by hand are at the bottom.

### Fixed
- **Setup's last page (and its other text boxes) were light grey with black text** in the dark wizard: now dark,
  like the rest.

## [1.0.0-beta.16] - 2026-11-03

### Changed
- **A phone port another device already has no longer stops your stream.** If something else on your network (a
  game console, a NAS, ...) already has UDP 5000, 8890 or TCP 1935 on the router, IRL Homekit now uses the next free
  outside port, leading to the same port on this PC, and keeps it from then on. The dashboard's Phone settings and
  its *Open in IRL Pro* link, Status and PHONE-SETUP.md all give the new port, and the dashboard says it changed.
  (The remote dashboard's 443 and 80 can't move: certificates need exactly those.)

## [1.0.0-beta.15] - 2026-11-03

### Added
- **Sign in with Twitch.** Setup's channels page (and Start menu → *IRL Homekit - Connect Twitch*) signs you in with
  Twitch in one step: a small window shows a code, Twitch opens in your browser, you click *Authorize*. IRL Homekit
  then has your Twitch stream key in its OBS, chat commands on, Studio's Twitch chat, title and category working, and
  clips on BRB playing as video, and it renews the sign-in by itself. No more TwitchTokenGenerator, tokens to paste
  or developer accounts. (A token you made by hand before keeps working.)
- **Clips on Be Right Back.** Switch on *Play clips on BRB* on the dashboard (new *Clips* card) and, when your
  connection drops, the BRB scene plays your past Twitch clips in random order, with a "reconnecting" banner on top
  and the clip's title and who clipped it. Pick how far back (week, month, year, all time). It uses Twitch's
  official API: with the *channel:manage:clips* permission on your Twitch chat token the clips play as plain video,
  otherwise in Twitch's own player. When there's nothing to play, your usual BRB screen shows. Kick and YouTube
  have no clips API yet, so it's Twitch only for now.
- **Set up IRL Pro in one tap.** Dashboard → *Phone settings* → Show → **Open in IRL Pro**: IRL Pro opens and
  offers to import the bonded connection and a backup one, with the server, passphrase and stream ID filled in. No
  typing addresses or passwords on the phone. (Or copy the link and paste it in IRL Pro's *Import Settings*.)
- **Find your dashboard address any time:** Start menu → *IRL Homekit - Dashboard address* shows it in big type with
  Copy and Open buttons and how to open it on your phone; it's also on the dashboard (*Home PC*) and in *Status*.

### Changed
- **Setup speaks plainer English** for people new to streaming setups: each page says what it's for and what to
  pick if you're not sure; the custom destination page only shows if you tick "I also stream somewhere else"; the
  dashboard password is made for you by default (shown at the end); the connection choices are "through my home
  internet" (recommended) or "through a free relay server".
- **Download button at the top of the README**, and the newest version is now GitHub's "Latest" release, with
  the installer always named `IRL-Homekit-Setup.exe`, so
  [github.com/CursedByJava/irl-homekit/releases/latest/download/IRL-Homekit-Setup.exe](https://github.com/CursedByJava/irl-homekit/releases/latest/download/IRL-Homekit-Setup.exe)
  always downloads the newest installer. (Betas stay "Latest" until there's a stable version.)

## [1.0.0-beta.14] - 2026-11-03

### Fixed
- **Ports you already forwarded in your router's own settings no longer show as "refused".** Some routers (Verizon's
  Fios router, for one) turn down the automatic request for a port that already has a forward, so with the remote
  dashboard set up, *Router ports* went red and said to forward 443 and 80 by hand, though they already were.
  IRL Homekit now counts those as forwarded. When it can, it also checks through your home's internet address that
  they reach this PC; if it can't check, it says to make sure they point at this PC.

## [1.0.0-beta.13] - 2026-11-03

### Added
- **No port forwarding and no accounts for most people: IRL Homekit opens its ports on your router by itself.** It
  asks the router (UPnP, or NAT-PMP on routers that use that, the way game consoles and video-call apps do) to pass
  the phone's ports to this PC, plus 80/443 with the remote dashboard, and renews them every 20 minutes while it
  runs. They're opened for 2 hours at a time, so they close by themselves when IRL Homekit is closed or uninstalled.
  Ports you forwarded by hand are left alone. Setup, Status and the dashboard (*Home PC → Router ports*, with a *Try
  again* button) show whether it worked and what to do if not: turn on UPnP or forward the ports by hand, or, when
  the router's own internet address is a private one (carrier-grade NAT, or a second router in front of yours), use
  the relay server, which is now only suggested to people who actually need it. Switch it off with `-PortMap Off`.
- **One-line install:** paste `irm https://raw.githubusercontent.com/CursedByJava/irl-homekit/main/get.ps1 | iex`
  into PowerShell. It downloads the newest release and starts the same installer, with no downloaded program for
  Windows Smart App Control to block (it blocks the not-yet-signed Setup.exe on some PCs).

### Changed
- Setup's *Phone connection* page now recommends the home router (opened automatically) and keeps the relay server
  for connections that can't take an incoming stream. The personal phone guide only lists port forwarding as a step
  when the router couldn't open the ports itself.

## [1.0.0-beta.12] - 2026-11-03

### Added
- **Setup.exe: a real Windows setup wizard.** Download `IRL-Homekit-Setup-<version>.exe` from the release and click
  through it instead of answering questions in a console window: your channels, which OBS scene collection, profile
  and overlays to bring over (picked from lists), a dashboard login, how your phone reaches the PC, the remote
  dashboard, and start with Windows. It then installs with a progress bar and the live log, and ends with your
  dashboard address, login and next steps. Running it again updates IRL Homekit and keeps your settings (tick a box to
  change the phone connection or remote dashboard). Built by the release workflow and attached to every release; the
  `.cmd` installer and the built-in updater keep working as before.
- **No port forwarding needed (optional relay server).** If you can't forward ports on your router (or your provider
  uses CGNAT), Setup can set you up with a free relay on Oracle Cloud's Always Free tier: it gives you a script to paste
  when you create the VM, and you enter the VM's address. Your phone then streams to the relay and your PC connects out
  to it, so the router needs nothing, and your home IP stays private. The PC connects with
  [WireGuard](https://www.wireguard.com) (the official signed Windows version, pinned and checksum-verified, so Smart
  App Control allows it), as a Windows service that only carries the relay's traffic. The remote dashboard works
  through it too, with HTTPS end to end and visitors' real addresses for the sign-in limits. The phone guide, Phone
  settings, Status, the dashboard's Home PC checks and DuckDNS all follow the relay. Step by step:
  [docs/RELAY.md](docs/RELAY.md).
- **Custom destination.** Stream to any RTMP server too (Restream, Facebook, Trovo, your own...): give it a name,
  server and stream key in Setup. It gets its own switch under **Stream to** on the dashboard, can be added or
  dropped mid-stream like Kick and YouTube, and carries the main stream when it's the only one on.
- **Channels are optional.** Skip Twitch, Kick and YouTube in Setup ("Skip for now") and add them later: run Setup
  again and tick "Also change my channels". Pasting a link works for all three, and YouTube takes your channel's
  link or @handle (it finds the channel ID for you). Without Twitch, chat commands stay off until you add it.
- **Setup's DuckDNS page picks up your token by itself** when you copy it on duckdns.org, suggests a name, and
  checks the name and token with DuckDNS before going on.
- **Phone settings on the dashboard.** A new card shows everything to enter in IRL Pro (bonded SRTLA server and
  passphrase, backup SRT server and stream ID, RTMP), each with a Copy button, so you can set up or fix the phone from
  anywhere instead of only from `PHONE-SETUP.md` on the PC. It stays hidden until you tap Show (it holds your stream
  passwords; keep it off camera) and hides itself again after 2 minutes. Only signed-in devices can load it.

### Changed
- OBS now reads the backup phone feed from MediaMTX with its own password instead of being trusted for coming from
  this PC, so nothing on the network can watch the feed without a password. Applied automatically by the update (the
  IRL scenes are rebuilt as usual).

### Fixed
- **The IRL Homekit OBS could crash at startup** after an update or an import from your regular OBS: the list of
  browser panels (the dashboard and Studio docks) could be saved in a form OBS can't read. It's written correctly
  now, and a broken one is repaired by the update. This also brings back the dashboard and Studio panels where they
  had gone missing.
- Status always showed the IP address from install in the IRL Pro settings, even with a DuckDNS name, and kept showing
  the old IP after your home IP changed. It now shows the same address as your phone guide: the DuckDNS name if you
  have one, otherwise your current home IP.

## [1.0.0-beta.11] - 2026-11-02

### Fixed
- The Sign out button could be cut off at the top of the dashboard and Studio. Nothing in the top bar shrinks or gets cut
  off any more: if it doesn't fit (narrow phones, larger text, the panel inside OBS), the bar scrolls sideways.

## [1.0.0-beta.10] - 2026-11-02

### Fixed
- The online / LIVE indicator at the top of the dashboard and Studio was cut off on phones. It now always shows in full
  (checked down to 320 px wide); on narrow phones Studio shows "LIVE · 1,234" instead of "… watching".

## [1.0.0-beta.9] - 2026-11-02

### Fixed
- After an OBS crash, IRL Homekit could fail to open or close properly: a crashed OBS can stay listed by Windows
  after it has exited (until the PC restarts), and IRL Homekit mistook it for the running one. Clicking the icon then
  showed nothing, and closing OBS made it restart in the tray. It now ignores processes that have already exited.
- **Opening IRL Homekit while it's running now shows its window** (Windows used to ignore the second click), also
  when it's in the tray.
- **Closing it always quits.** It no longer restarts hidden in the tray; only a start at sign-in begins in the tray.

### Added
- Your logo on the tray icon too, kept there when OBS changes it (e.g. when you go live).

## [1.0.0-beta.8] - 2026-11-02

### Added
- **Stream to** switches on the dashboard: choose Twitch, Kick and YouTube individually, e.g. stream to Twitch only.
  A platform that's off never goes live (no stray "went live" notifications). Kick and YouTube can be added or dropped
  while you're live. If Twitch is off, OBS's main stream goes to the next platform that's on, so the dashboard button,
  OBS's own button and `!start` in chat all respect the switches. Your choice is kept across updates.

### Changed
- The multistream plugin no longer starts Kick/YouTube on its own; IRL Homekit does, following the switches (the
  update changes this setting for you).

## [1.0.0-beta.7] - 2026-11-02

### Fixed
- Updating could fail with "access denied" when a crashed OBS was still holding its files (it can stay stuck closing
  until the PC restarts). The installer now skips unpacking tools that are already installed at the same version
  (faster updates), accepts files in use when they already match, and force-closes the whole OBS process tree.

## [1.0.0-beta.6] - 2026-11-02

### Fixed
- **OBS could crash when you pressed Start stream.** The dashboard asked OBS for its list of outputs every few seconds;
  in OBS 33 that request crashes OBS if it lands while the multistream plugin is creating the Kick/YouTube outputs.
  The dashboard no longer asks for it.
- **A crashed OBS that stayed on its crash window wasn't restarted.** IRL Homekit now notices when its OBS is running
  but not answering for 45 seconds, and restarts it.

## [1.0.0-beta.5] - 2026-11-02

### Changed
- **One sign-in for the dashboard and Studio**: signing in on one address signs you in on the other.
- **Keep me signed in** (ticked by default): your session renews every time you use it, so you stay signed in as long
  as you open it at least once every 30 days, instead of being signed out 30 days after signing in. Unticked, you're
  signed out when the browser closes.
- Opening the dashboard from a link in another app (Messages, Discord) no longer asks you to sign in again.
- Signing in from Studio brings you back to Studio. Existing sign-ins carry over.

## [1.0.0-beta.4] - 2026-11-02

### Changed
- The low-bitrate warning is now one small line in the bottom-left corner (signal bars, `Low bitrate`, live kbps),
  so it no longer covers the top of the stream.

## [1.0.0-beta.3] - 2026-11-01

### Fixed
- Installing on a PC without Node.js failed (Windows Installer error 1603, found by a clean-PC test). IRL Homekit
  now keeps its own copy of Node.js in `C:\IRLHomekit\node` (the official portable zip, checksum-verified): no
  installer, no system changes, and it works on PCs without winget.

### Added
- A clean-PC install test (Windows Sandbox: no Node.js, no winget) now passes: install, app start, uninstall.
- Screenshots of the IRL Homekit OBS and the dashboard in the README.
- `Uninstall-IRLHomekit.ps1 -Yes` uninstalls without questions (for scripts and tests).
- GitHub Discussions for questions and sharing setups, linked from the README and the new-issue page.
- Windows **Smart App Control** blocks are detected and explained: the installer test-runs each tool and says
  which ones Windows blocks and how to allow them; the dashboard shows it too, and IRL Homekit retries every minute
  instead of every few seconds.
## [1.0.0-beta.2] - 2026-11-01

### Added
- **Set up remote dashboard** (Start menu, also offered by the installer): choose a free DuckDNS name, your own
  domain, or this PC only. It walks you through each step (opens duckdns.org, shows the exact DNS records with
  GoDaddy / Cloudflare / Namecheap / Porkbun steps), sets up the web server and firewall, and checks DNS, router
  ports 80/443 and the HTTPS certificate, with a plain fix for anything missing.
- **Remote access** status on the dashboard (*Home PC*): working, or what to fix.

### Fixed
- Copies installed before version numbers existed now get updates (they were treated as stable and skipped betas).

### Changed
- Releases are published automatically when `VERSION` changes on `main`.

## [1.0.0-beta.1] - 2026-11-01

The first beta: IRL Homekit becomes an app you open and close, with its own OBS.

### Added
- **Its own OBS.** IRL Homekit downloads a portable copy of OBS Studio (33.0.1) into `C:\IRLHomekit\obs`, with
  its own settings. Your regular OBS is never changed, and you don't need OBS installed at all.
- **Open / close like an app.** One *IRL Homekit* icon on the desktop and in the Start menu. Closing its OBS window
  stops everything; crashes restart by themselves. Opening it again while it runs brings the window back.
- **Start with Windows**, on by default, with a switch on the dashboard (*Home PC*). The installer asks.
- **Runs as administrator** for better OBS performance, without a permission prompt each time (two Windows tasks).
- **IRL Homekit look:** its own OBS skin (OBS's dark theme in IRL Homekit's red-pink colours), the logo on the
  window and taskbar, and "IRL Homekit" in the title bar. Rounded app icon.
- **Dashboard and Studio as panels** inside the IRL Homekit OBS.
- **Import from your regular OBS:** every profile, scene collection, setting and plugin, in the installer or any
  time from the Start menu, with a backup first. Handles the OBS 33 plugin layout.
- **Double-click installer** (`Install IRL Homekit.cmd`), which also installs Node.js if it's missing.
- **Updates:** checks GitHub for a newer version when the app opens and on the dashboard, and installs it for you.
- **Uninstaller** in Settings > Apps.
- Version number and beta label in the installer, dashboard and Settings > Apps.

### Changed
- Updating keeps all your answers, passwords, stream keys and your start-with-Windows choice; re-running the
  installer asks nothing new.
- The IRL OBS uses WebSocket port 4456, so it never clashes with your regular OBS (4455).
- Tools moved from the desktop into the Start menu folder *IRL Homekit*.

### Removed
- The always-on background task and the Pause / Resume shortcuts (close the IRL Homekit OBS instead).

## [0.4.0] - 2026-11-01
### Added
- Choose your own dashboard username and password in the installer, and change it any time ("Change login"); the
  dashboard picks up a new login without a restart and signs every device out.
- "Forgot your login?" help on the sign-in page.
- Support the project: GitHub Sponsors, Ko-fi and Cash App links.
- [docs/DOMAIN.md](docs/DOMAIN.md): a free DuckDNS name or a cheap domain, step by step. DuckDNS names work out of
  the box and are kept pointed at your home IP.

## [0.3.0] - 2026-11-01
### Added
- Animated 1080p Starting Soon and Be Right Back screens (starfield background, animated dots).
- Live "low bitrate" banner on the LOW scenes, showing the phone's current bitrate.

## [0.2.1] - 2026-11-01
### Fixed
- The installer now copies the dashboard's font folder.

## [0.2.0] - 2026-11-01
### Added
- Apple-style redesign of the dashboard and Studio with the Inter font, app icon, light and dark mode.
- Kick categories are matched to Twitch's by name, with a chooser when Kick names them differently.

## [0.1.0] - 2026-11-01
### Added
- First version: bonded SRTLA ingest (go-irl), backup SRT/RTMP (MediaMTX), automatic LIVE / LOW / BRB scenes
  (NOALBS), multistreaming to Twitch, Kick and YouTube (obs-multi-rtmp), remote dashboard and Studio with HTTPS
  (Caddy), watchdog, and installer.

[Unreleased]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.20...HEAD
[1.0.0-beta.20]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.19...v1.0.0-beta.20
[1.0.0-beta.19]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.18...v1.0.0-beta.19
[1.0.0-beta.18]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.17...v1.0.0-beta.18
[1.0.0-beta.17]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.16...v1.0.0-beta.17
[1.0.0-beta.16]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.15...v1.0.0-beta.16
[1.0.0-beta.15]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.14...v1.0.0-beta.15
[1.0.0-beta.14]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.13...v1.0.0-beta.14
[1.0.0-beta.13]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.12...v1.0.0-beta.13
[1.0.0-beta.12]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.11...v1.0.0-beta.12
[1.0.0-beta.11]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.10...v1.0.0-beta.11
[1.0.0-beta.10]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.9...v1.0.0-beta.10
[1.0.0-beta.9]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.8...v1.0.0-beta.9
[1.0.0-beta.8]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.7...v1.0.0-beta.8
[1.0.0-beta.7]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.6...v1.0.0-beta.7
[1.0.0-beta.6]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.5...v1.0.0-beta.6
[1.0.0-beta.5]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.4...v1.0.0-beta.5
[1.0.0-beta.4]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.3...v1.0.0-beta.4
[1.0.0-beta.3]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.2...v1.0.0-beta.3
[1.0.0-beta.2]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.1...v1.0.0-beta.2
[1.0.0-beta.1]: https://github.com/CursedByJava/irl-homekit/compare/146fa7c...v1.0.0-beta.1
[0.4.0]: https://github.com/CursedByJava/irl-homekit/commit/146fa7c
[0.3.0]: https://github.com/CursedByJava/irl-homekit/commit/f31c39c
[0.2.1]: https://github.com/CursedByJava/irl-homekit/commit/19e7d7b
[0.2.0]: https://github.com/CursedByJava/irl-homekit/commit/9a4b851
[0.1.0]: https://github.com/CursedByJava/irl-homekit/commit/774b896
