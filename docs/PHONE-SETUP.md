IRL HOMEKIT: FINISH ON YOUR PHONE
=================================
Keep this file private: it has your passwords. (They're also in {{INSTALL_DIR}}\secrets.json.)

Four steps, about 5 minutes.

QUICKEST: SCAN A CODE
---------------------
On this PC: Start menu > IRL Homekit - Connect my phone. Point your phone's camera at the code and tap the link.
Your phone opens the dashboard already signed in, with Open in IRL Pro ready: that does Steps 1 and 2 for you.


STEP 1. Open the dashboard on your phone
----------------------------------------
On your phone, open Chrome (or Samsung Internet), tap the address bar at the top and type:

    {{DASHBOARD_URL}}

(Type it in the address bar, not in a Google search.) Sign in with:

    Username:  {{DASHBOARD_USER}}
    Password:  {{DASHBOARD_PASS}}

Then tap the browser's menu (three dots) > Add to Home screen, so it's one tap next time.

Does the address say "on this PC only"? Then set up the dashboard for your phone first: on this PC, Start menu >
IRL Homekit - Set up remote dashboard (free, about 5 minutes). Or skip to "Typing the settings by hand" at the bottom.


STEP 2. Set up IRL Pro in one tap
---------------------------------
On the dashboard (on your phone): Phone settings > Show > Open in IRL Pro. IRL Pro opens and asks to import
connections: tap yes. That's it: the server, passphrase and backup connection are all filled in.


STEP 3. Three phone settings that keep bonding working (Android)
-----------------------------------------------------------------
  1. Settings > Apps > IRL Pro > Battery > Unrestricted.
  2. Settings > Developer options > Mobile data always active > On.
     (No Developer options? Settings > About phone > Software information > tap Build number 7 times.)
  3. Samsung: Settings > Connections > Wi-Fi > Intelligent Wi-Fi > Switch to mobile data > Off.

In IRL Pro, on the IRL Homekit (bonded) connection, turn bonding on (mobile data + Wi-Fi).
Video: 1080p, 60 fps (30 if the phone gets hot), H.265/HEVC, adaptive bitrate on, up to 8000 kbps.


STEP 4. Go live
---------------
  1. Start streaming in IRL Pro. Within a few seconds the PC switches from Be Right Back to your live camera.
  2. On the dashboard, tap Start stream (or type !start in your Twitch chat).
  3. To finish, tap End stream (or !stop). If you only stop IRL Pro, viewers see Be Right Back, and the stream
     ends by itself after 20 minutes.

Test it once with Wi-Fi off on the phone, to be sure it works away from home.


YOUR INTERNET CONNECTION
------------------------
<!-- router -->
{{ROUTER_PORTS}}
    UDP 5000   bonded phone stream
    UDP 8890   backup phone stream (SRT)
    TCP 1935   backup phone stream (RTMP)
    TCP 443 and 80   the dashboard on your phone (only with a dashboard address)
{{ROUTER_AFTER}}
<!-- /router -->
<!-- relay -->
Your phone streams to your relay server at {{RELAY_HOST}}, and this PC connects to it by itself. Keep the relay
server running. If the phone can't connect, check the relay (docs/RELAY.md in the IRL Homekit repo). Its setup
script, in case you need to set it up again: {{INSTALL_DIR}}\relay\relay-vps.sh (it has your relay password).
<!-- /relay -->


GOOD TO KNOW
------------
- Open and close: the IRL Homekit icon on the desktop opens it; closing its OBS window stops everything. It opens
  by itself when you sign in to Windows (change that on the dashboard: Home PC > Start with Windows).
- Your dashboard address any time: Start menu > IRL Homekit - Dashboard address.
- Twitch: if you didn't sign in with Twitch in Setup, Start menu > IRL Homekit - Connect Twitch. That turns on
  chat commands and puts your stream key in.
- Kick and YouTube (optional): in the IRL Homekit OBS, Docks > Multiple output > edit Kick or YouTube, paste the
  server and stream key, tick enabled. The dashboard's Stream to switches turn each one on or off.
- New password: Start menu > IRL Homekit - Change login (it signs out every device).
- Comes back after a power cut: Win+R > netplwiz > untick "Users must enter a user name and password" (missing? first
  turn off Settings > Accounts > Sign-in options > "only allow Windows Hello sign-in").
- Something not working: Start menu > IRL Homekit - Status, or Save diagnostics for a bug report.
  Logs: {{INSTALL_DIR}}\logs


TYPING THE SETTINGS BY HAND (only if Step 2 didn't work)
--------------------------------------------------------
In IRL Pro, add a connection:
    Protocol:    SRTLA
    Server:      srtla://{{PHONE_HOST}}:{{PORT_BONDED}}
    Passphrase:  {{GOIRL_PASSPHRASE}}
    Stream ID:   (leave empty)
    Latency:     2000 ms (3000-4000 in crowded places)
    Bonding:     on
  No passphrase box? Use this as the server: srtla://{{PHONE_HOST}}:{{PORT_BONDED}}?passphrase={{GOIRL_PASSPHRASE}}

Backup connection (no bonding):
    Protocol:    SRT
    Server:      srt://{{PHONE_HOST}}:{{PORT_SRT}}
    Stream ID:   publish:live:{{MEDIAMTX_USER}}:{{MEDIAMTX_PASS}}
    Latency:     2000 ms

Last resort (RTMP): rtmp://{{PHONE_HOST}}:{{PORT_RTMP}}/live?user={{MEDIAMTX_USER}}&pass={{MEDIAMTX_PASS}}

Studio (combined chat, title and category on every platform): {{STUDIO_URL}} (same login)
