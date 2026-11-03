# Third-party software

IRL Homekit's installer downloads these official releases at install time and checks each file's SHA-256 before
using it. None of their code is included in this repository.

| Project | Version | License | Source |
|---|---|---|---|
| go-irl | v3.1.0 | AGPL-3.0 | https://github.com/e04/go-irl |
| MediaMTX | v1.21.3 | MIT | https://github.com/bluenviron/mediamtx |
| NOALBS | v2.21.0 | MIT | https://github.com/NOALBS/nginx-obs-automatic-low-bitrate-switching |
| obs-multi-rtmp | 0.7.4.5 | GPL-2.0 | https://github.com/sorayuki/obs-multi-rtmp |
| Caddy | v2.11.7 | Apache-2.0 | https://github.com/caddyserver/caddy |
| WireGuard for Windows (only with a relay server; signed MSI, checksum-verified) | 1.1.1 | MIT | https://www.wireguard.com |

On the relay VM, its setup script installs WireGuard tools (GPL-2.0) and HAProxy (GPL-2.0) from Ubuntu's own packages.

Setup.exe is built with Inno Setup (https://jrsoftware.org/isinfo.php, Inno Setup License).

Bundled in this repo: the Inter typeface (dashboard/public/fonts, SIL Open Font License 1.1, https://rsms.me/inter, license file included).

Also used, installed separately by you: OBS Studio (GPL-2.0), Node.js (MIT), ffmpeg (LGPL/GPL, self-test only).

Phone apps this works with: IRL Pro (Android), Moblin (iOS), BELABOX encoders.
