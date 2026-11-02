# Security

IRL Homekit puts a dashboard for your PC on the internet, so security reports are taken seriously.

## Reporting a problem

Please **don't open a public issue**. Report it privately on GitHub:
[Security → Report a vulnerability](https://github.com/CursedByJava/irl-homekit/security/advisories/new).
Include what you found, how to reproduce it, and the IRL Homekit version. You'll get a reply as soon as possible,
and a fix will be released as an update before details are made public.

## Supported versions

Only the latest release (including the latest beta) gets security fixes. The app checks for updates when you open
it and on the dashboard.

## How IRL Homekit protects you

- The dashboard is served over HTTPS only (Caddy + Let's Encrypt) and listens on the PC itself (127.0.0.1); only
  Caddy is reachable from outside.
- Your dashboard password is stored as a scrypt hash; sessions use 30-day HttpOnly, Secure, SameSite=Strict
  cookies; 5 wrong passwords lock sign-in for 15 minutes; strict Content Security Policy.
- The phone receivers need a passphrase (SRTLA) or a username and password (SRT/RTMP).
- OBS WebSocket, MediaMTX's API and the dashboard port are never opened on the router.
- Passwords, tokens and stream keys stay in `C:\IRLHomekit\secrets.json` and OBS's settings on your PC; nothing
  goes through a third-party server.
- Downloads in the installer are pinned versions checked against their SHA-256.
