# No port forwarding: the relay server

Normally your phone connects straight to your home PC: IRL Homekit opens the ports on your router by itself (or you
forward them by hand, `ROUTER.md`), and you don't need this page. If that can't work (an internet provider that
puts you behind carrier-grade NAT, which Setup and Status point out; a building's Wi-Fi; some 5G home routers), use
a **relay**: a small free cloud server that your phone connects to instead. It needs a free Oracle Cloud account.

```
Phone ──SRTLA / SRT / RTMP──▶ relay VM (public IP)  ◀══ tunnel ══  your home PC (IRL Homekit)
                                                        the PC dials OUT, so the router needs nothing
```

IRL Homekit's PC connects out to the relay and keeps that connection open; the relay passes the phone's streams (and
the remote dashboard, if you use it) back down it. Your home IP also stays private: viewers and anyone who sees your
phone settings only ever see the relay's address.

- **Cost:** free, on Oracle Cloud's Always Free tier (10 TB of outgoing traffic a month; a stream at 8 Mbps is about
  3.6 GB an hour). Oracle asks for a card to sign up, but Always Free resources aren't charged.
- **Delay:** pick the region nearest to you and it adds a few milliseconds, far less than SRT's 2-second buffer.
- **Software:** the PC connects to the relay with [WireGuard](https://www.wireguard.com), the open-source VPN, in
  its official signed Windows version (so Windows Smart App Control and antivirus allow it), pinned and
  checksum-verified. It runs as a Windows service that starts with Windows, and only carries the relay's own traffic:
  the rest of your PC's internet doesn't go through it. On the VM, the setup script installs WireGuard and HAProxy
  from Ubuntu's own packages. Only your PC (with your relay password) can connect, and the VM only passes on
  IRL Homekit's ports.

Setup.exe walks you through all of this on the **Phone connection** page. The steps in detail:

## 1. Create the VM (about 10 minutes)

1. Sign up at [cloud.oracle.com](https://cloud.oracle.com) and pick the **home region** nearest you (e.g. US East
   (Ashburn) for New York). The home region can't be changed later.
2. Optional but recommended: *Billing → Upgrade and manage payment → Pay As You Go*. You still pay nothing while you
   stay within the Always Free limits, and Oracle stops reclaiming "idle" Always Free VMs, which can otherwise
   happen to a relay you only use on stream days.
3. *Compute → Instances → Create instance*:
   - **Image:** Canonical Ubuntu (22.04 or 24.04).
   - **Shape:** `VM.Standard.E2.1.Micro` (AMD, always free) or `VM.Standard.A1.Flex` with 1 OCPU / 6 GB (Arm, always
     free; sometimes "out of capacity", just try again later or use the AMD one). Either is plenty for a relay.
   - **Networking:** keep "Assign a public IPv4 address" on.
   - **Advanced options → Management → Initialization script → Paste cloud-init script:** paste the relay setup script
     that Setup.exe shows you (the **Copy setup script** button). It's also saved as `C:\IRLHomekit\relay\relay-vps.sh`
     after installing. It contains your relay password: don't post it anywhere.
   - Click **Create**. The script runs by itself on first boot (give it 3-5 minutes: it installs WireGuard and HAProxy first).
4. Copy the VM's **Public IP address** from its page. That's what you enter in Setup.

## 2. Open the ports in Oracle's firewall (security list)

The setup script opens the VM's own firewall, but Oracle also has one in front of it:

*Your instance → Primary VNIC → Subnet → Security → the Default Security List → Add Ingress Rules*. Add these, each
with **Source CIDR** `0.0.0.0/0`:

| IP protocol | Destination port | What |
|---|---|---|
| UDP | `5000` | Bonded phone stream (SRTLA) |
| UDP | `8890` | Backup phone stream (SRT) |
| UDP | `51820` | The tunnel from your home PC (WireGuard) |
| TCP | `1935` | Backup phone stream (RTMP), optional |
| TCP | `80`, `443` | Remote dashboard, only if you use one |

## 3. Finish in Setup

Enter the public IP on the **Phone connection** page and finish. At the end Setup checks that your PC reached the
relay. Your IRL Pro settings (Phone settings on the dashboard, Status, and `PHONE-SETUP.md`) now use the relay's
address. With a DuckDNS name, IRL Homekit points the name at the relay for you.

## Checking and fixing

- **Start menu → IRL Homekit - Status** shows whether the relay is connected, and the dashboard shows it under
  *Home PC* (with a Restart button).
- *"the relay doesn't answer"*: UDP 51820 isn't open in the security list, the VM is stopped, or its setup script
  didn't run (or hasn't finished: give a new VM 3-5 minutes). On the VM:
  `sudo systemctl status wg-quick@irlhk irlhk-relay-web` and `sudo wg show` (a "latest handshake" means the PC got in).
- Still no handshake: the VM was set up with a different script (another relay password). Run the saved one again on
  the VM: `sudo bash relay-vps.sh` (copy `C:\IRLHomekit\relay\relay-vps.sh` over), or recreate the VM with it.
- *"the relay tunnel is missing"*: run Setup again (it sets the tunnel up), or as administrator:
  `C:\IRLHomekit\scripts\Set-IRLRelay.ps1 -WaitSeconds 60`.
- Connected but the phone can't reach it: check UDP 5000 / 8890 in the security list.
- Connected but the remote dashboard doesn't load: check TCP 80 / 443 in the security list.
- Moving to a new VM: create it with the same script and run Setup again with the new IP.
- Turning the relay off: run Setup again and choose **Router port forwarding** (then set up your router, `ROUTER.md`).
- Uninstalling IRL Homekit removes the tunnel but doesn't touch the VM (delete it in Oracle Cloud if you no longer
  need it) or the WireGuard app (Settings → Apps, if you don't use it for anything else).

Other free hosts work too if they give you a public IPv4 address and enough traffic: run the setup script on any
Ubuntu or Debian VM with `sudo bash relay-vps.sh`, and open the same ports in that host's firewall.
