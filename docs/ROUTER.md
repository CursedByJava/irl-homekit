# Router setup

Your phone connects to your home PC over the internet, so your router must pass these ports to the PC.

**Usually you don't need this page:** IRL Homekit asks the router to open them by itself (UPnP / NAT-PMP, which
most home routers have on) and keeps them open while it runs. Setup, Start menu → *IRL Homekit - Status* and the
dashboard (*Home PC → Router ports*) say whether that worked. Use the steps below when they say it didn't, or turn
on **UPnP** in the router's settings instead (often under *Advanced*, *NAT* or *Gaming*), then open IRL Homekit again.

Status says your router's internet address is a private one or that your provider uses carrier-grade NAT? Then
forwarding ports can't help; use a free relay server instead: [RELAY.md](RELAY.md).

| Protocol | Port | Needed for |
|---|---|---|
| UDP | 5000 | Bonded stream from IRL Pro / Moblin / BELABOX (go-irl, SRTLA) |
| UDP | 8890 | Backup stream, plain SRT (MediaMTX) |
| TCP | 1935 | Backup stream, RTMP (optional) |
| TCP | 443 | Remote dashboard over HTTPS (only with a domain) |
| TCP | 80 | Lets Caddy get the free HTTPS certificate (only with a domain) |

Forward each one to the PC's local IP (shown as `LAN IP` in `PHONE-SETUP.md`, e.g. `192.168.1.50`) with the
same port number on both sides. Then add a **DHCP reservation** for the PC so its local IP never changes.

## Verizon Fios (CR1000A / G3100 / E3200)
1. Open https://192.168.1.1 and sign in (admin password is on the router's sticker).
2. **Advanced** (top) → **Security & Firewall** → **Port Forwarding**.
3. For each row above: *Application* = any name, *Original Port* = port, *Protocol* = TCP or UDP,
   *Fwd to Addr* = your PC, *Fwd to Port* = same port, *Schedule* = Always → **Add to list**.
4. Press **Apply Changes**.
5. Reservation: **Advanced → Network Settings → Advanced Settings → DHCP / IP Address Distribution** (name varies
   by model) → your PC → *Static lease*.

## Xfinity / Comcast (XB6, XB7, XB8)
Use the Xfinity app: **WiFi → View WiFi equipment → Advanced settings → Port forwarding → Add port forward**,
pick the PC, choose *Manual setup*, enter each port and protocol.

## AT&T (BGW210 / BGW320)
https://192.168.1.254 → **Firewall → NAT/Gaming** → *Custom Services* to create each port, then assign them to the
PC under *Needed by Device*.

## Spectrum / Charter
Spectrum app → **Services → Internet → Advanced Settings → Port Forwarding → Add Port Forward**.

## Any other router
Look for *Port Forwarding*, *Virtual Servers*, *NAT* or *Applications & Gaming*. If you use a mesh system
(eero, Google/Nest Wifi, Deco), the setting is in its phone app.

## Can't forward ports? (CGNAT)
Check with the Status shortcut: if your router's WAN IP is in `100.64.0.0/10` or differs from your public IP,
your ISP uses CGNAT and forwarding won't work. Options:
- Ask the ISP for a public IPv4 (often free or a few dollars).
- Run go-irl in **server/client mode** with a small VPS as the public end (see the go-irl README), or use a hosted
  SRTLA relay such as BELABOX Cloud and point NOALBS at it.

## Test from outside
Turn Wi-Fi **off** on your phone (mobile data only) and go live in IRL Pro. The dashboard or the Status shortcut
should show the phone connected. Testing from inside your own Wi-Fi to your public IP may fail on routers without
NAT loopback even when forwarding is correct.
