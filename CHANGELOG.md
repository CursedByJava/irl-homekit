# Changelog

All notable changes to IRL Homekit. Versions follow [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`,
with `-beta.N` while the app is in beta. The format is based on [Keep a Changelog](https://keepachangelog.com).

> **IRL Homekit is in beta.** It works end to end, but expect rough edges, and things may change between betas.
> Please report problems on the [issues page](https://github.com/CursedByJava/irl-homekit/issues).

Each release is also published on the [Releases page](https://github.com/CursedByJava/irl-homekit/releases), which
is what the built-in update checker reads.

## [Unreleased]

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

[Unreleased]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.4...HEAD
[1.0.0-beta.4]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.3...v1.0.0-beta.4
[1.0.0-beta.3]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.2...v1.0.0-beta.3
[1.0.0-beta.2]: https://github.com/CursedByJava/irl-homekit/compare/v1.0.0-beta.1...v1.0.0-beta.2
[1.0.0-beta.1]: https://github.com/CursedByJava/irl-homekit/compare/146fa7c...v1.0.0-beta.1
[0.4.0]: https://github.com/CursedByJava/irl-homekit/commit/146fa7c
[0.3.0]: https://github.com/CursedByJava/irl-homekit/commit/f31c39c
[0.2.1]: https://github.com/CursedByJava/irl-homekit/commit/19e7d7b
[0.2.0]: https://github.com/CursedByJava/irl-homekit/commit/9a4b851
[0.1.0]: https://github.com/CursedByJava/irl-homekit/commit/774b896