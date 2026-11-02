# Getting a domain for your dashboard

A domain is optional. Without one, the dashboard only opens on the streaming PC itself. With one, you open
`https://your-name…` from your phone anywhere, with a free HTTPS certificate that IRL Homekit sets up for you.

You have two choices:

| | DuckDNS (free) | Your own domain (about $10/year) |
|---|---|---|
| Looks like | `https://willirl.duckdns.org` | `https://irl.yourname.com` |
| Cost | Free | Usually around $10/year for a `.com` |
| DNS records to add | None | Two |
| Follows your home IP when it changes | Yes, automatically | Only if you update it (or use the trick below) |
| Setup time | 2 minutes | 10 minutes |

## Option 1: free name from DuckDNS

1. Go to **https://www.duckdns.org** and sign in (GitHub, Google, Reddit or X account).
2. Under **sub domain**, type a name, for example `willirl`, and press **add domain**. You now own
   `willirl.duckdns.org`.
3. Copy the **token** shown at the top of the DuckDNS page.
4. Run the installer and answer:
   - Domain: `willirl.duckdns.org`
   - DuckDNS token: the token from step 3
5. Forward **TCP 80** and **TCP 443** on your router to the PC ([ROUTER.md](ROUTER.md)).

That's it. Your pages are:

- Dashboard: `https://willirl.duckdns.org`
- Studio: `https://studio.willirl.duckdns.org` (DuckDNS answers for every name under yours, so there's nothing to add)

**Why the token matters:** home internet IPs change every so often. With the token, IRL Homekit updates DuckDNS
every 5 minutes, and your personal `PHONE-SETUP.md` tells IRL Pro to use `willirl.duckdns.org` instead of the
raw IP. When your IP changes, your stream and dashboard keep working with no changes on the phone.

Good to know: DuckDNS is a free, volunteer-run service. The address always ends in `.duckdns.org`.

## Option 2: your own domain

Buy one from a low-cost registrar. Compare the **renewal** price, not just the first-year deal:

- **Cloudflare Registrar** (https://www.cloudflare.com/products/registrar/): sells domains at cost with no
  markup. A `.com` is usually around $10–11 a year.
- **Porkbun** (https://porkbun.com): low prices and free privacy protection. Endings like `.xyz` or `.online` are
  often a few dollars for the first year.
- **Namecheap** (https://www.namecheap.com): frequent first-year deals.

Skip the extras they offer at checkout (hosting, email, "SSL certificates"). IRL Homekit gets its HTTPS
certificate for free.

Already own a domain for a website? You can use it. Adding the two records below doesn't affect your site.

### Add two DNS records

In your registrar's DNS settings, add:

| Type | Name | Value |
|---|---|---|
| A | `irl` | your public IP |
| A | `studio` | your public IP |

Your public IP is in `PHONE-SETUP.md` (or run the **Status** shortcut). Then run the installer with
Domain `irl.yourname.com`. Studio will be at `studio.yourname.com`.

### When your home IP changes

The Status shortcut warns you. Update both A records to the new IP. To make it automatic, combine both options:
make a free DuckDNS name, then use **CNAME** records instead of A records:

| Type | Name | Value |
|---|---|---|
| CNAME | `irl` | `willirl.duckdns.org` |
| CNAME | `studio` | `willirl.duckdns.org` |

Then install with `-Domain irl.yourname.com -DuckDnsName willirl -DuckDnsToken <token>`. IRL Homekit keeps the
DuckDNS name current, and your own domain follows it.

## Check that it works

1. On the PC, run `nslookup irl.yourname.com` (or your DuckDNS name). It should show your public IP.
2. Open the address on your phone **with Wi-Fi off**. The first visit can take up to a minute while the free
   certificate is issued.
3. Still not loading? See [TROUBLESHOOTING.md](TROUBLESHOOTING.md). Usually ports 80/443 aren't forwarded yet, or
   the DNS record hasn't spread (wait 5–10 minutes).
