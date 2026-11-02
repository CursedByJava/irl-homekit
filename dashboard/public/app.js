'use strict';
const $ = (id) => document.getElementById(id);

// ---------------------------------------------------------------- login page
if ($('err')) {
  const e = new URLSearchParams(location.search).get('e');
  if (e === 'locked') $('err').innerHTML = '<b>Sign-in is locked for 15 minutes.</b> There were 5 wrong tries in a row from this network. Wait, then try again.';
  if (e) $('err').classList.add('show');
} else {
  dashboard();
}

function dashboard() {
  // On the public domain the two pages live on separate hosts (irl. and studio.).
  if (location.hostname.startsWith('irl.')) document.querySelector('[data-studio]').href = 'https://' + location.hostname.replace(/^irl\./, 'studio.') + '/';
  // Signal thresholds match NOALBS: under 1000 kbps = LOW scene, under 300 kbps = BRB scene.
  const LOW = 1000, OFFLINE = 300, METER_MAX = 8000;
  const SERVICE_INFO = {
    obs: ['IRL Homekit OBS', 'Mixes your scenes and sends the stream to Twitch, Kick and YouTube.'],
    'go-irl': ['Bonded receiver (go-irl)', 'Receives the bonded 5G + Wi-Fi signal from IRL Pro.'],
    mediamtx: ['Backup receiver (MediaMTX)', 'Receives the backup SRT/RTMP connection.'],
    noalbs: ['Auto-switcher (NOALBS)', 'Switches LIVE / LOW / BRB scenes based on your signal.'],
    caddy: ['Web server (Caddy)', 'Serves this page securely over HTTPS from your home PC.'],
  };
  let s = null; let lastMsg = 0; let busy = false;

  // ---------- helpers
  const fmtDur = (ms) => { if (!ms) return '0:00'; const t = Math.floor(ms / 1000), h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), x = t % 60; return (h ? h + ':' + String(m).padStart(2, '0') : m) + ':' + String(x).padStart(2, '0'); };
  const fmtKbps = (k) => (k >= 1000 ? (k / 1000).toFixed(1) + ' Mbps' : k + ' kbps');
  function el(tag, cls, text) { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }

  let toastTimer;
  function toast(kind, title, why) {
    const t = $('toast'); t.className = 'toast show ' + kind; t.replaceChildren(el('b', '', title));
    if (why) t.append(el('span', 'why', why));
    clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove('show'), kind === 'error' ? 9000 : 4000);
  }

  // Turns raw errors into "what happened + why + what to do".
  function explain(action, msg) {
    msg = String(msg || '');
    if (/not connected|disconnected/i.test(msg)) return ['OBS isn\'t responding.', 'OBS on your home PC is closed or restarting. The watchdog reopens it within about 30 seconds. Try again then.'];
    if (/timeout/i.test(msg)) return ['OBS took too long to answer.', 'The home PC may be overloaded. Wait a few seconds and try again.'];
    if (/401|login required/i.test(msg)) return ['You were signed out.', 'Your session expired. Sign in again to keep controlling the stream.'];
    if (/Failed to fetch|NetworkError|network/i.test(msg)) return ['Couldn\'t reach your home PC.', 'Your phone or the home internet dropped for a moment. Check your signal and try again.'];
    if (/SCENES_WHILE_LIVE/.test(msg)) return ['Can\'t update scenes while live.', 'Updating swaps OBS to your main collection for a few seconds, which viewers would see. End the stream first, update, then go live.'];
    if (action === 'updateScenes') return ['Scenes weren\'t updated.', 'The PC said: "' + msg + '". Your current scenes are unchanged.'];
    if (/FPS_WHILE_LIVE/.test(msg)) return ['Can\'t change the frame rate while live.', 'OBS only switches frame rate when the stream and recording are stopped. End the stream, switch, then go live again (takes about 10 seconds).'];
    if (action === 'startStream' && /active|already/i.test(msg)) return ['The stream is already running.', 'Nothing to do. You\'re live.'];
    if (action === 'stopStream' && /not active/i.test(msg)) return ['The stream is already off.', 'Nothing to do.'];
    if (action === 'startStream') return ['The stream didn\'t start.', 'OBS said: "' + msg + '". Check that the stream key in the IRL Homekit profile is still valid.'];
    return ['That didn\'t work.', 'OBS said: "' + msg + '". Try again. If it keeps happening, use Quick fixes or restart the service below.'];
  }

  async function act(body, okTitle, okWhy) {
    if (busy) return; busy = true;
    try {
      const r = await fetch('/api/action', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-IRLHK': '1' }, body: JSON.stringify(body), credentials: 'same-origin' });
      if (r.status === 401) { location.href = '/login'; return; }
      const j = await r.json().catch(() => ({ ok: false, error: 'HTTP ' + r.status }));
      if (!j.ok) { const [t, w] = explain(body.action, j.error); toast('error', t, w); }
      else if (okTitle) toast('success', okTitle, okWhy || j.note);
    } catch (e) { const [t, w] = explain(body.action, e.message); toast('error', t, w); }
    finally { busy = false; }
  }

  function confirmBox(title, text, yesLabel, noLabel, danger = true) {
    return new Promise((resolve) => {
      const d = $('confirm'); $('confirmTitle').textContent = title; $('confirmText').textContent = text;
      $('confirmYes').textContent = yesLabel; $('confirmNo').textContent = noLabel;
      $('confirmYes').className = 'btn ' + (danger ? 'stop' : 'go');
      const done = (v) => { d.close(); $('confirmYes').onclick = $('confirmNo').onclick = null; resolve(v); };
      $('confirmYes').onclick = () => done(true); $('confirmNo').onclick = () => done(false);
      d.oncancel = () => done(false);
      d.showModal();
    });
  }

  // ---------- live data
  function connect() {
    const es = new EventSource('/events', { withCredentials: true });
    es.onmessage = (ev) => { lastMsg = Date.now(); s = JSON.parse(ev.data); render(); };
    es.onerror = () => { es.close(); fetch('/events', { method: 'HEAD' }).then((r) => { if (r.status === 401) location.href = '/login'; }).catch(() => {}); setTimeout(connect, 3000); };
  }
  setInterval(() => {
    const stale = Date.now() - lastMsg > 5000;
    const b = $('linkBanner');
    if (stale && lastMsg) {
      b.innerHTML = '<b>Lost connection to your home PC.</b> Reconnecting… Your stream keeps running on its own. If this lasts more than a minute, the PC may be off or your home internet may be down.';
      b.classList.add('show'); $('liveText').textContent = 'No link'; $('livePill').className = 'pill warn';
    } else b.classList.remove('show');
  }, 1000);
  connect();

  // ---------- rendering
  function render() {
    renderTop(); renderSignal(); renderStream(); renderScenes(); renderAudio(); renderServices(); renderHistory(); renderUpdate();
  }

  function renderTop() {
    const p = $('livePill'), t = $('liveText');
    if (!s.obs.connected) { p.className = 'pill warn'; t.textContent = 'OBS offline'; }
    else if (s.stream.reconnecting) { p.className = 'pill warn'; t.textContent = 'Reconnecting'; }
    else if (s.stream.active) { p.className = 'pill live'; t.textContent = 'LIVE ' + fmtDur(s.stream.duration); }
    else { p.className = 'pill'; t.textContent = 'Offline'; }
  }

  function renderSignal() {
    const b = s.bonded, k = s.backup;
    const src = b.online ? 'bonded' : k.online ? 'backup' : null;
    const d = src === 'bonded' ? b : src === 'backup' ? k : null;
    $('tagBonded').className = 'tag' + (b.online ? ' on' : '') + (src === 'bonded' ? ' active' : '');
    $('tagBackup').className = 'tag' + (k.online ? ' on' : '') + (src === 'backup' ? ' active' : '');
    const q = $('sigQuality'), m = $('sigMeter');
    if (!d) {
      $('sigSource').textContent = 'IRL Pro isn\'t sending to your home PC.';
      $('sigKbps').textContent = '0'; q.className = 'quality q-none'; q.textContent = 'No signal';
      $('sigDesc').textContent = s.stream.active
        ? 'Viewers see your Be Right Back scene. Start streaming in IRL Pro and you\'ll be back on automatically.'
        : 'Open IRL Pro and tap Go Live. Your video shows up here within a few seconds.';
      m.style.width = '0%'; $('sigRtt').textContent = '–'; $('sigLoss').textContent = '–'; $('sigLinks').textContent = '–';
      $('links').replaceChildren(); return;
    }
    $('sigSource').textContent = src === 'bonded'
      ? 'Coming in over the bonded connection (5G + Wi-Fi combined).'
      : 'Coming in over the backup connection' + (k.type === 'rtmpConn' ? ' (RTMP).' : ' (SRT, no bonding).') + (k.codecs ? ' Video: ' + k.codecs + '.' : '');
    $('sigKbps').textContent = d.kbps.toLocaleString();
    let cls, label, desc, color;
    if (d.kbps < OFFLINE) { cls = 'q-none'; label = 'Too weak'; color = 'var(--red)'; desc = 'Signal is almost gone. Viewers see your Be Right Back scene until it recovers.'; }
    else if (d.kbps < LOW) { cls = 'q-weak'; label = 'Weak'; color = 'var(--amber)'; desc = 'Low bitrate. Viewers see the "LOW SIGNAL" banner. Move toward open sky or better coverage.'; }
    else if (d.kbps < 4000) { cls = 'q-good'; label = 'Good'; color = 'var(--green)'; desc = 'You\'re on stream. Picture quality is OK and improves as bitrate goes up.'; }
    else { cls = 'q-excellent'; label = 'Excellent'; color = 'var(--green)'; desc = 'Strong signal. You\'re on stream in full quality.'; }
    if (d.loss > 5) desc += ' High packet loss (' + d.loss + '%), so expect some stutter.';
    q.className = 'quality ' + cls; q.textContent = label; $('sigDesc').textContent = desc;
    m.style.width = Math.min(100, (d.kbps / METER_MAX) * 100) + '%'; m.style.background = color;
    $('sigRtt').textContent = d.rtt != null ? d.rtt + ' ms' : '–';
    $('sigLoss').textContent = d.loss != null ? d.loss + '%' : '–';
    const links = src === 'bonded' ? b.links || [] : [];
    $('sigLinks').textContent = src === 'bonded' ? String(links.length) : '1';
    $('links').replaceChildren(...links.map((l, i) => {
      const row = el('div', 'link'); const meter = el('div', 'meter'); const bar = el('span');
      bar.style.width = Math.min(100, (l.kbps / METER_MAX) * 100) + '%'; meter.append(bar);
      row.append(el('span', '', 'Link ' + (i + 1)), meter, el('span', 'num', fmtKbps(l.kbps))); return row;
    }));
  }

  function renderStream() {
    const st = s.stream, on = s.obs.connected;
    $('upTime').textContent = st.active ? fmtDur(st.duration) : '–';
    $('outKbps').textContent = st.active ? fmtKbps(st.kbps) : '–';
    $('dropped').textContent = st.active && st.total ? ((st.skipped / st.total) * 100).toFixed(1) + '%' : '–';
    const btn = $('streamBtn'); btn.disabled = !on;
    if (st.active) { btn.className = 'btn stop block'; btn.textContent = 'End stream'; }
    else { btn.className = 'btn go block'; btn.textContent = on ? 'Start stream' : 'Start stream (OBS offline)'; }
    // frame rate
    const fps = (s.video || {}).fps, locked = st.active || s.record.active;
    for (const b of [$('fps60'), $('fps30')]) { b.classList.toggle('on', Number(b.dataset.fps) === fps); b.disabled = !on || locked; }
    $('fpsDesc').textContent = !fps ? 'What viewers get on Twitch, Kick and YouTube.'
      : locked ? 'Streaming at ' + fps + ' fps. End the stream to change it.'
      : (fps === 60 ? 'Smooth motion. Best on a strong signal.' : 'Easier on a weak signal, a hot phone or a busy PC.');
    // multistream outputs
    const outs = s.outputs || [];
    $('outputsTag').textContent = st.active ? (outs.length + ' output' + (outs.length === 1 ? '' : 's') + ' live') : 'Twitch · Kick · YouTube';
    $('outputs').replaceChildren(...(st.active ? outs.map((o) => {
      const it = el('div', 'item'); const dot = el('span', 'status-dot ' + (o.reconnecting ? 'warn' : 'ok'));
      const g = el('div', 'grow'); g.append(el('div', 'title', o.name === 'adv_stream' || o.name === 'simple_stream' ? 'Main stream (Twitch)' : o.name),
        el('div', 'desc', o.reconnecting ? 'Reconnecting to the platform…' : 'Sending'));
      it.append(dot, g); return it;
    }) : []));
    // preview
    const img = $('previewImg');
    if (on && s.previewAt) { img.src = '/preview.jpg?t=' + s.previewAt; $('previewEmpty').hidden = true; img.hidden = false; }
    else { img.hidden = true; $('previewEmpty').hidden = false; $('previewEmpty').textContent = on ? 'Loading preview…' : 'OBS isn\'t running, so there\'s no preview. The watchdog restarts it within about 30 seconds.'; }
    $('previewScene').textContent = s.scene ? 'On stream: ' + s.scene : '–';
    // recording
    $('recBtn').textContent = s.record.active ? 'Stop recording' : 'Start recording';
    $('recBtn').disabled = !on;
    $('recDesc').textContent = s.record.active ? 'Recording for ' + fmtDur(s.record.duration) + ' on the home PC.' : 'Saves a local copy on the home PC.';
  }

  let sceneKey = '';
  function renderScenes() {
    const base = s.meta.baseCollection;
    $('updateScenesRow').hidden = !base;
    $('updateScenesBtn').disabled = !s.obs.connected || s.stream.active || s.record.active || $('updateScenesBtn').textContent !== 'Update scenes';
    if (base) $('updateScenesDesc').textContent = 'Edited your "' + base + '" collection in OBS? This copies those changes onto the IRL scenes. Only while offline.';
    const key = s.scenes.join('|') + '#' + s.scene;
    if (key === sceneKey) return; sceneKey = key;
    if (!s.scenes.length) return;
    $('scenes').replaceChildren(...s.scenes.map((name) => {
      const auto = s.meta.autoScenes.includes(name);
      const b = el('button', 'scene' + (auto ? ' irl' : '') + (name === s.scene ? ' current' : ''));
      b.append(el('span', 'name', name), el('span', 'badge', name === s.scene ? 'On stream' : auto ? 'Auto' : 'Scene'));
      b.onclick = () => { if (name !== s.scene) act({ action: 'setScene', scene: name }, 'Switched to ' + name + '.'); };
      return b;
    }));
  }

  let audioKey = '';
  function renderAudio() {
    const key = JSON.stringify(s.inputs); if (key === audioKey) return; audioKey = key;
    if (!s.inputs.length) return;
    const desc = s.meta.audioInputs || {};
    $('audio').replaceChildren(...s.inputs.map((i) => {
      const it = el('div', 'item'); const g = el('div', 'grow'); g.append(el('div', 'title', i.name), el('div', 'desc', desc[i.name] || ''));
      const t = el('button', 'toggle' + (i.muted ? ' muted' : ''), i.muted ? 'Muted' : 'On');
      t.setAttribute('aria-pressed', String(!i.muted)); t.title = i.muted ? 'Tap to unmute' : 'Tap to mute';
      t.onclick = () => act({ action: 'toggleMute', input: i.name }, i.muted ? i.name + ' unmuted.' : i.name + ' muted.');
      it.append(g, t); return it;
    }));
  }

  let updKey = '';
  function renderUpdate() {
    const u = s.update, key = JSON.stringify(u) + s.version;
    if (key === updKey) return; updKey = key;
    const beta = /-/.test(s.version || '');
    const vl = $('versionLine'); vl.replaceChildren();
    if (s.version) { vl.append('IRL Homekit ' + s.version); if (beta) vl.append(el('span', 'badge-beta', 'Beta')); }
    const b = $('updateBanner');
    if (!u) { b.classList.remove('show'); return; }
    $('updateTitle').textContent = 'IRL Homekit ' + u.latest + ' is available.';
    $('updateText').textContent = ' You have ' + s.version + '. Updating takes about 2 minutes and keeps all your settings.';
    $('updateNotes').href = u.url; b.classList.add('show');
  }

  let svcKey = '';
  function renderServices() {
    const sv = s.services || {}; const key = JSON.stringify(sv) + s.autoStart + JSON.stringify(s.stats);
    if (key === svcKey) return; svcKey = key;
    const down = Object.keys(SERVICE_INFO).filter((k) => sv[k] === false);
    const st = s.stats || {};
    const as = $('autoStart');
    as.classList.toggle('muted', !s.autoStart); as.textContent = s.autoStart ? 'On' : 'Off'; as.setAttribute('aria-pressed', String(!!s.autoStart));
    $('autoStartDesc').textContent = s.autoStart
      ? 'IRL Homekit opens by itself (minimized) when the PC signs in, so this page is always reachable.'
      : 'Off: after a restart, IRL Homekit (and this page) stays closed until someone opens it on the PC.';
    $('pcSummary').textContent = down.length ? down.length + ' part' + (down.length > 1 ? 's are' : ' is') + ' not running. IRL Homekit restarts them within 10–30 seconds.'
      : 'Everything is running.' + (st.cpu != null ? ' OBS: ' + st.cpu + '% CPU, ' + st.fps + ' fps.' : '');
    const hb = $('healthBanner');
    if (st.renderSkipped > 0 && s.stream.active && st.fps && st.fps < 55) { hb.innerHTML = '<b>The home PC is struggling.</b> OBS is rendering at ' + st.fps + ' fps instead of 60. Close other programs on the PC.'; hb.classList.add('show'); }
    else hb.classList.remove('show');
    $('services').replaceChildren(...Object.entries(SERVICE_INFO).filter(([k]) => k in sv).map(([k, [title, d]]) => {
      const it = el('div', 'item'); const ok = sv[k];
      const g = el('div', 'grow'); g.append(el('div', 'title', title), el('div', 'desc', ok === false ? 'Not running. Restarting automatically…' : d));
      it.append(el('span', 'status-dot ' + (ok ? 'ok' : ok === false ? 'bad' : '')), g);
      if (k !== 'obs') {
        const b = el('button', 'btn small ghost', 'Restart');
        b.onclick = async () => {
          const what = {
            noalbs: 'Auto-switching pauses for about 10 seconds. Your stream keeps running.',
            caddy: 'This page disconnects for about 10 seconds, then reconnects by itself. Your stream keeps running.',
          }[k] || 'If your phone is sending through it, viewers see the Be Right Back scene for about 10–15 seconds.';
          const yes = await confirmBox('Restart ' + title + '?', what, 'Restart', 'Keep running');
          if (yes) act({ action: 'restartService', service: k }, title + ' is restarting.', 'It comes back within about 10 seconds.');
        };
        it.append(b);
      }
      return it;
    }));
  }

  let histKey = '';
  function renderHistory() {
    const key = JSON.stringify(s.switches); if (key === histKey) return; histKey = key;
    if (!s.switches.length) return;
    const word = { Normal: 'Back to', Low: 'Weak signal →', Offline: 'Signal lost →' };
    $('history').replaceChildren(...s.switches.map((e) => {
      const r = el('div', 'ev'); const t = new Date(e.t);
      r.append(el('span', 'num', t.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })));
      const d = el('span'); d.append((word[e.kind] || e.kind) + ' ', el('b', '', e.scene)); r.append(d); return r;
    }));
  }

  // ---------- buttons
  $('streamBtn').onclick = async () => {
    if (!s) return;
    if (s.stream.active) {
      const yes = await confirmBox('End the stream?', 'This ends your broadcast on Twitch, Kick and YouTube. IRL Pro keeps running on your phone.', 'End stream', 'Keep streaming');
      if (yes) act({ action: 'stopStream' }, 'Stream ended.', 'You\'re offline on all platforms.');
    } else {
      const noSignal = !s.bonded.online && !s.backup.online;
      const yes = await confirmBox('Go live?', noSignal
        ? 'Your phone isn\'t connected yet, so viewers will see the Be Right Back scene until IRL Pro starts sending.'
        : 'You\'ll go live on Twitch, plus Kick and YouTube if they\'re enabled.', 'Go live', 'Not yet', false);
      if (yes) act({ action: 'startStream' }, 'Starting stream…', 'You\'re live in a few seconds.');
    }
  };
  $('updateScenesBtn').onclick = async () => {
    const base = s.meta.baseCollection;
    const yes = await confirmBox('Update scenes from "' + base + '"?', 'OBS switches to "' + base + '" for about 5 seconds, then the IRL scenes are rebuilt with your latest overlays. A backup of the current version is saved on the PC.', 'Update scenes', 'Cancel', false);
    if (!yes) return;
    $('updateScenesBtn').disabled = true; $('updateScenesBtn').textContent = 'Updating…';
    await act({ action: 'updateScenes' }, 'Scenes updated.');
    $('updateScenesBtn').disabled = false; $('updateScenesBtn').textContent = 'Update scenes';
  };
  for (const b of [$('fps60'), $('fps30')]) {
    b.onclick = () => { if (!b.classList.contains('on')) act({ action: 'setFps', fps: Number(b.dataset.fps) }, 'Frame rate set to ' + b.dataset.fps + ' fps.', 'Applies to your next stream on all platforms.'); };
  }
  $('recBtn').onclick = () => act({ action: s.record.active ? 'stopRecord' : 'startRecord' }, s.record.active ? 'Recording stopped.' : 'Recording started.');
  $('updateBtn').onclick = async () => {
    if (!s.update) return;
    const yes = await confirmBox('Update to ' + s.update.latest + '?', 'IRL Homekit closes on the PC, updates and reopens by itself in about 2 minutes. This page goes offline meanwhile, then reconnects. Your settings, stream keys and passwords are kept.', 'Update now', 'Not now');
    if (yes) act({ action: 'installUpdate' }, 'Updating IRL Homekit…', 'It reopens in about 2 minutes; this page reconnects by itself.');
  };
  $('autoStart').onclick = async () => {
    if (s.autoStart) {
      const yes = await confirmBox('Stop starting with Windows?', 'After the PC restarts, IRL Homekit and this page stay offline until someone opens IRL Homekit on the PC.', 'Turn off', 'Keep on');
      if (!yes) return;
    }
    act({ action: 'setAutoStart', on: !s.autoStart }, s.autoStart ? 'IRL Homekit no longer starts with Windows.' : 'IRL Homekit now starts with Windows.');
  };
  document.querySelectorAll('[data-action]').forEach((b) => {
    b.onclick = () => act({ action: b.dataset.action }, b.dataset.action === 'restartPhoneFeed' ? 'Phone feed reloaded.' : 'Overlays reloaded.');
  });
}
