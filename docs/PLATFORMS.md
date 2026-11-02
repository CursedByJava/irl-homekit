# Connecting Twitch, Kick and YouTube to Studio

Studio (`https://studio.<your-domain>`) shows live status and viewers for all three platforms, a combined chat, and
lets you change your title/category everywhere at once. Each platform needs its own one-time connection.
Everything stays on your PC: tokens are saved in `secrets.json`, nothing goes through a third-party server.

| | Live status | Chat (read) | Chat (send) | Title | Category |
|---|---|---|---|---|---|
| Twitch | ✅ | ✅ | ✅ | ✅ | ✅ |
| Kick | ✅ | ✅ (webhooks) | ✅ | ✅ | ✅ (matched by name) |
| YouTube | ✅ | ✅ while live | ✅ while live | ✅ | – (YouTube has no game categories for streams) |

Twitch's go-live notification text can't be changed by any outside tool; Studio links to the right Twitch page.

## Twitch
1. https://twitchtokengenerator.com → enable only **chat:read**, **chat:edit**, **channel:manage:broadcast** →
   *Generate Token* → *Authorize* → solve the CAPTCHA.
2. Start menu → **IRL Homekit - Twitch chat token**, and paste the Access and Refresh tokens.

## Kick (about 3 minutes)
1. kick.com → **Settings → Developer → Create new**.
2. Fill in:
   - **Application Name:** no spaces, e.g. `IRLHomekitStudio`
   - **Redirect URL:** `https://studio.<your-domain>/oauth/kick/callback`
   - **Enable webhooks:** on, URL `https://studio.<your-domain>/webhooks/kick`
   - **Scopes:** Read user information, Read channel information, Update channel information, Write to Chat feed,
     Subscribe to events. Nothing else is needed.
3. **Create App**, then copy the **Client ID** and **Client Secret**.
4. Run `scripts\Set-PlatformApps.ps1` on the PC and paste them (it checks them with Kick).
5. Open Studio → **Connect** next to Kick → **Allow Access**.

## YouTube (about 10 minutes, free)
1. https://console.cloud.google.com/projectcreate → create a project (any name).
2. **APIs & Services → Library → YouTube Data API v3 → Enable**.
3. **Google Auth Platform → Get started**: app name, your email, audience **External**, contact email, agree → Create.
4. **Branding**: home page `https://studio.<your-domain>/about`, privacy policy `https://studio.<your-domain>/privacy`
   (both pages are built in) → Save.
5. **Audience → Publish app → Confirm.** Without this, Google signs you out of YouTube every 7 days.
6. **Clients → Create client → Web application**, authorized redirect URI
   `https://studio.<your-domain>/oauth/youtube/callback` → Create. Copy the Client ID and secret **now**; Google shows
   the secret only once.
7. Run `scripts\Set-PlatformApps.ps1` and paste them.
8. Studio → **Connect** next to YouTube → pick the Google account that owns your channel → *Advanced → Go to …*
   (Google warns because the app is yours and unverified; that's expected) → **Continue**.

YouTube allows 10,000 API units per day. Studio reads YouTube chat every 12 seconds only while you're live
(about 1,500 units/hour), which covers 6+ hours of live chat a day. Sending a YouTube chat message costs 50 units.

Also set your YouTube channel ID (`UC…`) as `youtubeChannelId` in `settings.json` (the installer asks for it).

## Disconnecting
- Twitch: https://www.twitch.tv/settings/connections → TwitchTokenGenerator → Disconnect
- Kick: kick.com → Settings → Connections
- Google: https://myaccount.google.com/permissions
