// IRL Homekit remote dashboard. No npm dependencies (Node 22+).
// Listens on 127.0.0.1 only; Caddy terminates HTTPS for your domain (settings.json "domain") and proxies here.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import dns from 'node:dns/promises';
import { execFile, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '..');
const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8').replace(/^﻿/, ''));
const CONFIG_FILE = path.join(DIR, 'config.json');
let cfg = readJson(CONFIG_FILE);
const secrets = readJson(`${ROOT}/secrets.json`);
const settings = readJson(`${ROOT}/settings.json`);
const PORT = cfg.port || 8090;
// Windows task that opens IRL Homekit at sign-in (scripts/Install-Shortcuts.ps1 -AutoStart On|Off).
const SIGNIN_TASK = 'IRL Homekit (sign-in)';
function readAutoStart() {
  return new Promise((resolve) => execFile('schtasks.exe', ['/query', '/tn', SIGNIN_TASK, '/fo', 'csv', '/nh'], { windowsHide: true }, (err, out) => {
    if (!err) state.autoStart = !/"Disabled"/i.test(out);
    resolve();
  }));
}
const SESSION_DAYS = 30;

function log(...a) { console.log(new Date().toISOString(), ...a); }

// ---------------------------------------------------------------- OBS WebSocket v5 client
class Obs {
  constructor(url, password) { this.url = url; this.password = password; this.ws = null; this.ready = false; this.pending = new Map(); this.seq = 0; this.connect(); }
  connect() {
    let ws;
    try { ws = new WebSocket(this.url); } catch { return this.retry(); }
    this.ws = ws;
    ws.onmessage = (ev) => this.onMessage(JSON.parse(ev.data));
    ws.onclose = () => { this.ready = false; for (const p of this.pending.values()) p.reject(new Error('OBS disconnected')); this.pending.clear(); this.retry(); };
    ws.onerror = () => {};
  }
  retry() { clearTimeout(this.rt); this.rt = setTimeout(() => this.connect(), 3000); }
  sha(s) { return crypto.createHash('sha256').update(s).digest('base64'); }
  onMessage(m) {
    if (m.op === 0) {
      const d = { rpcVersion: 1, eventSubscriptions: 64 };   // Outputs events: stream started / stopped
      if (m.d.authentication) d.authentication = this.sha(this.sha(this.password + m.d.authentication.salt) + m.d.authentication.challenge);
      this.ws.send(JSON.stringify({ op: 1, d }));
    } else if (m.op === 2) { this.ready = true; log('OBS connected'); this.onReady?.(); }
    else if (m.op === 5) { this.onEvent?.(m.d.eventType, m.d.eventData || {}); }
    else if (m.op === 7) {
      const p = this.pending.get(m.d.requestId); if (!p) return; this.pending.delete(m.d.requestId);
      if (m.d.requestStatus.result) p.resolve(m.d.responseData || {}); else p.reject(new Error(m.d.requestStatus.comment || `code ${m.d.requestStatus.code}`));
    }
  }
  req(requestType, requestData = {}) {
    if (!this.ready) return Promise.reject(new Error('OBS not connected'));
    const requestId = String(++this.seq);
    return new Promise((resolve, reject) => {
      this.pending.set(requestId, { resolve, reject });
      this.ws.send(JSON.stringify({ op: 6, d: { requestType, requestId, requestData } }));
      setTimeout(() => { if (this.pending.delete(requestId)) reject(new Error('OBS timeout')); }, 5000);
    });
  }
}
const obs = new Obs(`ws://127.0.0.1:${settings.obsWebsocketPort || 4455}`, secrets.obsWebsocketPassword);

// ---------------------------------------------------------------- live state
const state = {
  obs: { connected: false }, stream: {}, record: {}, stats: {}, video: {}, scene: '', scenes: [], outputs: [], inputs: [],
  bonded: { online: false }, backup: { online: false }, services: {}, switches: [], updated: 0,
  meta: { autoScenes: settings.autoScenes || [], audioInputs: settings.audioInputs || {}, baseCollection: settings.baseCollection || '' },
};
let preview = null; let previewAt = 0;

// ---------------------------------------------------------------- where the stream goes (Twitch / Kick / YouTube switches)
// OBS's main stream output goes to the first platform that's switched on (Twitch, else Kick, else YouTube), so every
// way of starting the stream (dashboard, the OBS button, !start in chat) respects the switches. The other platforms
// that are on are started through obs-multi-rtmp's per-target hotkeys when the main stream starts, and stopped with
// it; platforms that are off are never started (no stray "went live" notifications). Their own auto-start
// ("sync-start") is switched off by the installer, so IRL Homekit decides.
const PLATFORMS = ['twitch', 'kick', 'youtube'];
const PLATFORM_NAMES = { twitch: 'Twitch', kick: 'Kick', youtube: 'YouTube' };
const profileDir = () => path.join(settings.obsConfigDir || '', 'basic', 'profiles', String(settings.obsProfile || 'IRL Homekit').replace(/[^A-Za-z0-9_-]/g, '_'));
settings.streamTo = { twitch: true, kick: true, youtube: true, ...(settings.streamTo || {}) };
const extraLive = new Set();   // multi-rtmp targets IRL Homekit started for the current stream

function saveSettings() {
  const file = path.join(ROOT, 'settings.json');
  const disk = readJson(file); disk.streamTo = settings.streamTo;   // only touch our key; the installer owns the rest
  fs.writeFileSync(file, JSON.stringify(disk, null, 2));
}
// Stream keys/servers: Twitch from the profile's main stream settings (remembered in secrets.json, since the main
// output may later point at Kick or YouTube), Kick and YouTube from obs-multi-rtmp's targets.
function endpoints() {
  const ep = {};
  try {
    const svc = readJson(path.join(profileDir(), 'service.json'));
    if (svc.type === 'rtmp_common' && /twitch/i.test(svc.settings?.service || '') && svc.settings?.key && secrets.streamTwitch?.key !== svc.settings.key) {
      saveSecrets({ streamTwitch: { type: svc.type, settings: svc.settings } });
    }
  } catch { }
  if (secrets.streamTwitch?.settings?.key) ep.twitch = { main: { type: secrets.streamTwitch.type, settings: secrets.streamTwitch.settings } };
  try {
    for (const t of readJson(path.join(profileDir(), 'obs-multi-rtmp.json')).targets || []) {
      const p = PLATFORMS.find((x) => new RegExp(PLATFORM_NAMES[x], 'i').test(t.name || ''));
      if (p && p !== 'twitch' && t['service-param']?.key) {
        ep[p] = { id: t.id, main: { type: 'rtmp_custom', settings: { server: t['service-param'].server, key: t['service-param'].key, use_auth: false } } };
      }
    }
  } catch { }
  return ep;
}
function primaryPlatform(ep = endpoints()) { return PLATFORMS.find((p) => settings.streamTo[p] && ep[p]) || null; }
function platformState() {
  const ep = endpoints(), primary = primaryPlatform(ep);
  state.platformsOut = { primary, list: PLATFORMS.map((p) => ({ id: p, name: PLATFORM_NAMES[p], on: !!settings.streamTo[p], ready: !!ep[p],
    live: !!state.stream?.active && (p === primary || extraLive.has(p)) })) };
}
// Point OBS's main output at the first platform that's on. Only possible while not streaming.
async function applyMainOutput() {
  if (!obs.ready) return;
  const ep = endpoints(), primary = primaryPlatform(ep);
  if (!primary) return;
  const cur = await obs.req('GetStreamServiceSettings').catch(() => null);
  if (!cur || (await obs.req('GetStreamStatus')).outputActive) return;
  const want = ep[primary].main;
  if (cur.streamServiceType === want.type && cur.streamServiceSettings?.key === want.settings.key) return;
  await obs.req('SetStreamServiceSettings', { streamServiceType: want.type, streamServiceSettings: want.settings });
  log('main stream output now goes to', PLATFORM_NAMES[primary]);
}
async function startExtras() {
  const ep = endpoints(), primary = primaryPlatform(ep);
  for (const p of ['kick', 'youtube']) {
    if (p === primary || !settings.streamTo[p] || !ep[p] || extraLive.has(p)) continue;
    await obs.req('TriggerHotkeyByName', { hotkeyName: `obs-multi-rtmp.start.${ep[p].id}` }).then(() => { extraLive.add(p); log('started', PLATFORM_NAMES[p]); }, (e) => log('could not start', p, e.message));
  }
}
async function stopExtra(p) {
  const ep = endpoints(); if (!ep[p]) return;
  await obs.req('TriggerHotkeyByName', { hotkeyName: `obs-multi-rtmp.stop.${ep[p].id}` }).catch(() => {});
  extraLive.delete(p); log('stopped', PLATFORM_NAMES[p]);
}
obs.onReady = () => { applyMainOutput().catch((e) => log('main output', e.message)); };
obs.onEvent = (type, d) => {
  if (type !== 'StreamStateChanged') return;
  if (d.outputState === 'OBS_WEBSOCKET_OUTPUT_STARTED') startExtras().catch((e) => log('extras', e.message));
  if (d.outputState === 'OBS_WEBSOCKET_OUTPUT_STOPPED') {
    for (const p of [...extraLive]) stopExtra(p);
    applyMainOutput().catch(() => {});   // switches changed while live take effect for the next stream
  }
};

// go-irl stats (only sent while a stream is coming in)
let goirlLast = 0; const linkPrev = new Map();
function goirlConnect() {
  let ws;
  try { ws = new WebSocket('ws://127.0.0.1:8888/ws'); } catch { return setTimeout(goirlConnect, 3000); }
  ws.onmessage = (ev) => {
    let m; try { m = JSON.parse(ev.data); } catch { return; }
    if (m.type !== 'reader' || !m.stats) return;
    const i = m.stats.Instantaneous || {}, a = m.stats.Accumulated || {};
    const now = Date.now();
    const links = (m.links || []).map((l) => {
      const prev = linkPrev.get(l.id); linkPrev.set(l.id, { b: l.rxBytes, t: now });
      const kbps = prev && now > prev.t ? Math.max(0, Math.round(((l.rxBytes - prev.b) * 8) / (now - prev.t))) : 0;
      return { id: l.id, kbps };
    });
    goirlLast = now;
    state.bonded = { online: true, kbps: Math.round((i.MbpsRecvRate || 0) * 1000), rtt: Math.round(i.MsRTT || 0),
      loss: +(i.PktRecvLossRate || 0).toFixed(2), buffer: i.MsRecvBuf || 0, lost: a.PktRecvLoss || 0, dropped: a.PktRecvDrop || 0, links };
  };
  ws.onclose = () => setTimeout(goirlConnect, 3000);
  ws.onerror = () => {};
}
goirlConnect();

// MediaMTX backup input
let mtxPrev = null;
async function pollMediamtx() {
  try {
    const r = await fetch('http://127.0.0.1:9997/v3/paths/get/live');
    if (!r.ok) throw new Error('offline');
    const p = await r.json(); const now = Date.now();
    const kbps = mtxPrev && p.ready ? Math.max(0, Math.round(((p.bytesReceived - mtxPrev.b) * 8) / (now - mtxPrev.t))) : 0;
    mtxPrev = { b: p.bytesReceived, t: now };
    let rtt = null;
    if (p.source?.type === 'srtConn') {
      const c = await (await fetch(`http://127.0.0.1:9997/v3/srtconns/get/${p.source.id}`)).json().catch(() => null);
      if (c) rtt = Math.round(c.msRTT);
    }
    state.backup = { online: !!p.ready, kbps, rtt, type: p.source?.type || '', codecs: (p.tracks2 || []).map((t) => t.codec).join(' + ') || (p.tracks || []).join(' + ') };
  } catch { mtxPrev = null; state.backup = { online: false }; }
}

async function pollObs() {
  state.obs.connected = obs.ready;
  if (!obs.ready) return;
  try {
    // Never GetOutputList: in OBS 33 it crashes OBS if it runs while an output is being created (e.g. the multistream
    // plugin starting Kick/YouTube the moment you press Start stream). The stream status has what we need.
    const [scene, stream, record, stats, list, video] = await Promise.all([
      obs.req('GetCurrentProgramScene'), obs.req('GetStreamStatus'), obs.req('GetRecordStatus'), obs.req('GetStats'),
      obs.req('GetSceneList'), obs.req('GetVideoSettings')]);
    state.video = { fps: Math.round(video.fpsNumerator / video.fpsDenominator), width: video.outputWidth, height: video.outputHeight };
    state.scene = scene.currentProgramSceneName;
    state.scenes = list.scenes.slice().reverse().map((s) => s.sceneName);
    state.stream = { active: stream.outputActive, reconnecting: stream.outputReconnecting, duration: stream.outputDuration,
      bytes: stream.outputBytes, skipped: stream.outputSkippedFrames, total: stream.outputTotalFrames, congestion: stream.outputCongestion };
    const now = Date.now();
    state.stream.kbps = state._sb && stream.outputActive ? Math.max(0, Math.round(((stream.outputBytes - state._sb.b) * 8) / (now - state._sb.t))) : 0;
    state._sb = { b: stream.outputBytes, t: now };
    state.record = { active: record.outputActive, duration: record.outputDuration };
    state.stats = { cpu: +stats.cpuUsage.toFixed(1), fps: +stats.activeFps.toFixed(1), renderSkipped: stats.renderSkippedFrames,
      outputSkipped: stats.outputSkippedFrames, memory: Math.round(stats.memoryUsage) };
    state.outputs = stream.outputActive ? [{ name: 'adv_stream', kind: 'rtmp_output', reconnecting: stream.outputReconnecting }] : [];
    if (!stream.outputActive && extraLive.size) extraLive.clear();
    platformState();
  } catch (e) { /* OBS busy or reconnecting */ }
}

async function pollInputs() {
  if (!obs.ready) return;
  try {
    const want = Object.keys(settings.audioInputs || {});
    const res = [];
    for (const name of want) {
      try { const m = await obs.req('GetInputMute', { inputName: name }); res.push({ name, muted: m.inputMuted }); } catch { }
    }
    state.inputs = res;
  } catch { }
}

async function grabPreview() {
  if (!obs.ready || !state.scene || clients.size === 0) return;
  try {
    const r = await obs.req('GetSourceScreenshot', { sourceName: state.scene, imageFormat: 'jpg', imageWidth: 640, imageCompressionQuality: 55 });
    preview = Buffer.from(r.imageData.split(',')[1], 'base64'); previewAt = Date.now();
  } catch { }
}

function pollServices() {
  execFile('tasklist', ['/FO', 'CSV', '/NH'], { windowsHide: true }, (err, out) => {
    if (err) return;
    const names = new Set(out.split(/\r?\n/).map((l) => l.split('","')[0].replace(/^"/, '').toLowerCase()));
    // OBS: your normal OBS may be open too, so "running" means IRL Homekit's own OBS answering on its WebSocket.
    state.services = { obs: obs.ready, mediamtx: names.has('mediamtx.exe'), 'go-irl': names.has('go-irl.exe'), noalbs: names.has('noalbs.exe') };
    if (settings.domain) state.services.caddy = names.has('caddy.exe');
    if (settings.relayHost) state.services.relay = relayUp;   // relay tunnel (docs/RELAY.md), see pollRelay
    // Programs Windows Smart App Control refused to start (written by the app, scripts/Start-IRLHomekit.ps1).
    try { state.blocked = JSON.parse(fs.readFileSync(path.join(ROOT, 'logs', 'blocked.json'), 'utf8')); } catch { state.blocked = []; }
  });
}

// Relay tunnel (WireGuard service, scripts/Set-IRLRelay.ps1): up when the relay answers at its tunnel address.
let relayUp = false;
function pollRelay() {
  if (!settings.relayHost) return;
  execFile('ping', ['-n', '1', '-w', '2000', '10.66.66.1'], { windowsHide: true }, (err, out) => { relayUp = !err && /TTL=/i.test(out); });
}

function pollSwitches() {
  fs.readFile(`${ROOT}/logs/noalbs.out.log`, 'utf8', (err, txt) => {
    if (err) return;
    const lines = txt.split(/\r?\n/).filter((l) => l.includes('Scene switched to')).slice(-8).reverse();
    state.switches = lines.map((l) => { const m = l.match(/^(\S+).*Scene switched to \[(\w+)\] (.*)$/); return m ? { t: m[1], kind: m[2], scene: m[3].trim() } : null; }).filter(Boolean);
  });
}

// OBS's media-source "restart" keeps the old decoder, so a phone that reconnects with a different codec or resolution
// (e.g. H.264 -> H.265, 60 -> 30 fps) shows garbage. Changing the input URL forces OBS to rebuild the source; do that
// on every reconnect so each phone session starts with a fresh decoder.
async function reopenInput(name) {
  if (!obs.ready) return;
  try {
    const { inputSettings } = await obs.req('GetInputSettings', { inputName: name });
    if (!inputSettings.input) return;
    await obs.req('SetInputSettings', { inputName: name, inputSettings: { input: 'udp://127.0.0.1:1' } });
    await new Promise((r) => setTimeout(r, 300));
    await obs.req('SetInputSettings', { inputName: name, inputSettings: { input: inputSettings.input } });
    log('reopened', name);
  } catch (e) { log('reopen failed', name, e.message); }
}
let wasOnline = null; // unknown until the first tick, so a dashboard restart mid-stream doesn't blip the feed
setInterval(() => {
  if (Date.now() - goirlLast > 3000) { state.bonded = { online: false }; linkPrev.clear(); }
  const [bondedName, backupName] = settings.phoneInputs || [];
  if (wasOnline && state.bonded.online && !wasOnline.bonded && bondedName) reopenInput(bondedName);
  if (wasOnline && state.backup.online && !wasOnline.backup && backupName) reopenInput(backupName);
  wasOnline = { bonded: !!state.bonded.online, backup: !!state.backup.online };
}, 1000);
setInterval(pollObs, 1000); setInterval(pollMediamtx, 1000); setInterval(pollInputs, 3000);
setInterval(pollServices, 5000); setInterval(pollSwitches, 3000); setInterval(grabPreview, 2000);
pollServices(); pollSwitches();
setInterval(pollRelay, 15000); pollRelay();
setInterval(readAutoStart, 30000); readAutoStart();

// ---------------------------------------------------------------- updates (GitHub releases)
const VERSION = (() => { try { return fs.readFileSync(path.join(ROOT, 'VERSION'), 'utf8').trim(); } catch { return ''; } })();
state.version = VERSION;
function parseVer(v) { const [core, pre] = String(v).replace(/^v/, '').split('-', 2); return { n: (core.split('.').map(Number).concat([0, 0, 0])).slice(0, 3), pre: pre ? pre.split('.') : [] }; }
function cmpVer(a, b) {
  for (let i = 0; i < 3; i++) if (a.n[i] !== b.n[i]) return Math.sign(a.n[i] - b.n[i]);
  if (!a.pre.length || !b.pre.length) return (a.pre.length ? -1 : 0) + (b.pre.length ? 1 : 0);
  for (let i = 0; i < Math.max(a.pre.length, b.pre.length); i++) {
    if (i >= a.pre.length) return -1; if (i >= b.pre.length) return 1;
    const x = a.pre[i], y = b.pre[i], xn = /^\d+$/.test(x), yn = /^\d+$/.test(y);
    if (xn && yn) { if (+x !== +y) return Math.sign(+x - +y); } else if (x !== y) return xn ? -1 : yn ? 1 : (x < y ? -1 : 1);
  }
  return 0;
}
async function checkForUpdate() {
  if (!VERSION) return;
  try {
    const cur = parseVer(VERSION);
    const channel = settings.updateChannel || (cur.pre.length ? 'beta' : 'stable');   // betas get betas, stable gets stable
    const r = await fetch('https://api.github.com/repos/CursedByJava/irl-homekit/releases?per_page=30', { headers: { 'User-Agent': 'IRL-Homekit-dashboard' } });
    if (!r.ok) return;
    let best = null;
    for (const rel of await r.json()) {
      if (rel.draft || (rel.prerelease && channel !== 'beta')) continue;
      const v = parseVer(rel.tag_name);
      if (!best || cmpVer(v, best.v) > 0) best = { v, rel };
    }
    state.update = best && cmpVer(best.v, cur) > 0
      ? { latest: best.rel.tag_name.replace(/^v/, ''), notes: String(best.rel.body || '').slice(0, 800), url: best.rel.html_url } : null;
  } catch (e) { log('update check failed:', e.message); }
}
setInterval(checkForUpdate, 6 * 3600e3); setTimeout(checkForUpdate, 20000);

// ---------------------------------------------------------------- remote access health (same checks as Setup-RemoteDashboard.ps1)
async function checkRemote() {
  if (!settings.domain) { state.remote = { domain: '' }; return; }
  const names = [settings.domain, settings.studioDomain].filter(Boolean);
  const r = { domain: settings.domain, studio: settings.studioDomain, ok: true, problem: '' };
  try {
    // Names must point at the relay server when there is one (docs/RELAY.md), else at this PC's home IP.
    const ip = settings.relayHost ? await relayIp() : (await (await fetch('https://api.ipify.org', { signal: AbortSignal.timeout(8000) })).text()).trim();
    const where = settings.relayHost ? 'your relay' : 'your home IP';
    const resolver = new dns.Resolver(); resolver.setServers(['1.1.1.1', '8.8.8.8']);
    for (const n of names) {
      const got = await resolver.resolve4(n).catch(() => []);
      if (!got.includes(ip)) { r.ok = false; r.problem = got.length ? `${n} points to ${got[0]}, but ${where} is ${ip}. Update its DNS record.` : `${n} has no DNS record.`; break; }
    }
    const certDir = path.join(ROOT, 'caddy', 'data', 'certificates', 'acme-v02.api.letsencrypt.org-directory');
    if (r.ok) for (const n of names) if (!fs.existsSync(path.join(certDir, n, `${n}.crt`))) {
      r.ok = false; r.problem = `No HTTPS certificate for ${n} yet: usually ${settings.relayHost ? "the relay VM doesn't let ports 80 and 443 in" : "the router isn't forwarding ports 80 and 443"}.`; break;
    }
  } catch (e) { r.ok = null; r.problem = 'Could not check (no internet?)'; }
  state.remote = r;
}
setInterval(checkRemote, 10 * 60e3); setTimeout(checkRemote, 15000);

// ---------------------------------------------------------------- platforms (Studio page)
// Twitch: Helix API + IRC chat with the token from Set-TwitchBotToken.ps1 (TwitchTokenGenerator's client id).
// Kick: public channel endpoint for live status (Kick's official API needs a developer app for chat/title).
// YouTube: public channel page for live status (chat/title need a Google API key / OAuth app).
state.platforms = { twitch: { connected: false }, kick: { connected: false }, youtube: { connected: false } };
const chat = []; let chatSeq = 0;
function pushChat(m) { m.id = ++chatSeq; m.ts = Date.now(); chat.push(m); if (chat.length > 300) chat.shift(); }
const tw = { id: secrets.twitchClientId, token: secrets.twitchBotToken, user: secrets.twitchUserId, login: settings.twitchChannel };
async function helix(method, pathQ, body) {
  const r = await fetch('https://api.twitch.tv/helix/' + pathQ, { method, headers: { 'Client-Id': tw.id, Authorization: 'Bearer ' + tw.token, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  if (r.status === 204) return {};
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(`Twitch ${r.status}: ${j.message || r.statusText}`);
  return j;
}
async function pollTwitch() {
  if (!tw.id || !tw.token || !tw.user) return;
  try {
    const [st, ch] = await Promise.all([helix('GET', 'streams?user_id=' + tw.user), helix('GET', 'channels?broadcaster_id=' + tw.user)]);
    const live = st.data?.[0]; const c = ch.data?.[0] || {};
    state.platforms.twitch = { connected: true, live: !!live, viewers: live ? live.viewer_count : 0, startedAt: live?.started_at || null,
      title: c.title, category: c.game_name, categoryId: c.game_id, url: `https://twitch.tv/${tw.login}` };
  } catch (e) { state.platforms.twitch = { ...state.platforms.twitch, error: e.message }; }
}
function twitchChat() {
  if (!tw.token || !tw.login) return;
  let ws; try { ws = new WebSocket('wss://irc-ws.chat.twitch.tv:443'); } catch { return setTimeout(twitchChat, 10000); }
  tw.chat = ws;
  ws.onopen = () => { ws.send('CAP REQ :twitch.tv/tags twitch.tv/commands'); ws.send('PASS oauth:' + tw.token); ws.send('NICK ' + tw.login); ws.send('JOIN #' + tw.login); };
  ws.onmessage = (ev) => {
    for (const line of String(ev.data).split('\r\n')) {
      if (!line) continue;
      if (line.startsWith('PING')) { ws.send('PONG :tmi.twitch.tv'); continue; }
      const m = line.match(/^@(\S+) :([^!]+)!\S+ PRIVMSG #\S+ :(.*)$/);
      if (!m) continue;
      const tags = Object.fromEntries(m[1].split(';').map((t) => t.split('=')));
      pushChat({ platform: 'twitch', user: tags['display-name'] || m[2], color: tags.color || '', text: m[3], mod: tags.mod === '1', broadcaster: (tags.badges || '').includes('broadcaster') });
    }
  };
  ws.onclose = () => { tw.chat = null; setTimeout(twitchChat, 5000); };
  ws.onerror = () => {};
}
// --- Kick official API (needs the developer app's client id/secret in secrets.json, then one sign-in) ---
const KICK_SCOPES = 'user:read channel:read channel:write chat:write events:subscribe';
const kickRedirect = () => `https://${settings.studioDomain || settings.domain}/oauth/kick/callback`;
const oauthStates = new Map(); // state -> { verifier, exp }
function saveSecrets(patch) {
  Object.assign(secrets, patch);
  const onDisk = readJson(`${ROOT}/secrets.json`); Object.assign(onDisk, patch);
  fs.writeFileSync(`${ROOT}/secrets.json`, JSON.stringify(onDisk, null, 2));
}
async function kickToken() {
  if (!secrets.kickRefreshToken) return null;
  if (secrets.kickAccessToken && (secrets.kickExpiresAt || 0) > Date.now() + 60e3) return secrets.kickAccessToken;
  const r = await fetch('https://id.kick.com/oauth/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: secrets.kickRefreshToken, client_id: secrets.kickClientId, client_secret: secrets.kickClientSecret }) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j.access_token) { log('kick refresh failed', r.status, JSON.stringify(j).slice(0, 200)); if (r.status === 400 || r.status === 401) saveSecrets({ kickAccessToken: '', kickRefreshToken: '' }); return null; }
  saveSecrets({ kickAccessToken: j.access_token, kickRefreshToken: j.refresh_token || secrets.kickRefreshToken, kickExpiresAt: Date.now() + (j.expires_in || 3600) * 1000 });
  return j.access_token;
}
async function kickApi(method, pathQ, body) {
  const token = await kickToken(); if (!token) throw new Error('KICK_NOT_CONNECTED');
  const r = await fetch('https://api.kick.com/public/v1/' + pathQ, { method, headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json', Accept: 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  if (r.status === 204) return {};
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(`Kick ${r.status}: ${j.message || r.statusText}`);
  return j;
}
async function kickAfterLogin() {
  const u = await kickApi('GET', 'users'); const me = u.data?.[0];
  if (me) saveSecrets({ kickUserId: me.user_id, kickLogin: me.name });
  const sub = await kickApi('POST', 'events/subscriptions', { events: [{ name: 'chat.message.sent', version: 1 }, { name: 'livestream.status.updated', version: 1 }], method: 'webhook' });
  log('kick connected as', me?.name, 'subscriptions:', JSON.stringify(sub.data || sub).slice(0, 300));
}
let kickPublicKey = null; let kickKeyAt = 0; const kickSeen = new Set();
const kickInfo = { title: secrets.kickLastTitle || '', category: secrets.kickLastCategory || '' };
function rememberKick(patch) { Object.assign(kickInfo, patch); saveSecrets({ kickLastTitle: kickInfo.title, kickLastCategory: kickInfo.category }); }
async function kickVerify(headers, raw) {
  if (!kickPublicKey || Date.now() - kickKeyAt > 6 * 3600e3) {
    const j = await (await fetch('https://api.kick.com/public/v1/public-key')).json();
    kickPublicKey = j.data?.public_key; kickKeyAt = Date.now();
  }
  const id = headers['kick-event-message-id'], ts = headers['kick-event-message-timestamp'], sig = headers['kick-event-signature'];
  if (!id || !ts || !sig || !kickPublicKey) return false;
  return crypto.verify('sha256', Buffer.from(`${id}.${ts}.${raw}`), kickPublicKey, Buffer.from(sig, 'base64'));
}
async function pollKick() {
  const slug = settings.kickChannel || settings.twitchChannel; if (!slug) return;
  if (secrets.kickRefreshToken) {
    try {
      const j = await kickApi('GET', 'channels'); const c = j.data?.[0] || {};
      // Kick only reports title/category while live, so fall back to what Studio last set.
      if (c.stream_title) kickInfo.title = c.stream_title;
      if (c.category?.name) kickInfo.category = c.category.name;
      state.platforms.kick = { connected: true, authorized: true, live: !!c.stream?.is_live, viewers: c.stream?.viewer_count || 0,
        startedAt: c.stream?.is_live ? c.stream.start_time : null, title: kickInfo.title, category: kickInfo.category, url: 'https://kick.com/' + (c.slug || slug) };
      return;
    } catch (e) { log('kick api poll failed:', e.message); }
  }
  try {
    const r = await fetch('https://kick.com/api/v2/channels/' + slug, { headers: { 'User-Agent': 'Mozilla/5.0 IRL-Homekit', Accept: 'application/json' } });
    if (!r.ok) throw new Error('Kick ' + r.status);
    const j = await r.json(); const ls = j.livestream;
    state.platforms.kick = { connected: true, authorized: false, canAuthorize: !!secrets.kickClientId, live: !!ls?.is_live, viewers: ls?.viewer_count || 0,
      title: ls?.session_title || '', category: ls?.categories?.[0]?.name || '', url: 'https://kick.com/' + slug, readOnly: true };
  } catch (e) { state.platforms.kick = { connected: false, error: e.message, url: 'https://kick.com/' + slug }; }
}
// --- YouTube Data API (Google OAuth client in secrets.json, then one sign-in) ---
const YT_SCOPE = 'https://www.googleapis.com/auth/youtube.force-ssl';
const ytRedirect = () => `https://${settings.studioDomain || settings.domain}/oauth/youtube/callback`;
const yt = { broadcast: null, chatId: null, pageToken: null, chatTimer: null };
async function ytToken() {
  if (!secrets.youtubeRefreshToken) return null;
  if (secrets.youtubeAccessToken && (secrets.youtubeExpiresAt || 0) > Date.now() + 60e3) return secrets.youtubeAccessToken;
  const r = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: secrets.youtubeRefreshToken, client_id: secrets.youtubeClientId, client_secret: secrets.youtubeClientSecret }) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j.access_token) { log('youtube refresh failed', r.status, j.error); if (j.error === 'invalid_grant') saveSecrets({ youtubeAccessToken: '', youtubeRefreshToken: '' }); return null; }
  saveSecrets({ youtubeAccessToken: j.access_token, youtubeExpiresAt: Date.now() + (j.expires_in || 3600) * 1000 });
  return j.access_token;
}
async function ytApi(method, pathQ, body) {
  const token = await ytToken(); if (!token) throw new Error('YOUTUBE_NOT_CONNECTED');
  const r = await fetch('https://www.googleapis.com/youtube/v3/' + pathQ, { method, headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  if (r.status === 204) return {};
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(`YouTube ${r.status}: ${j.error?.errors?.[0]?.reason || j.error?.message || r.statusText}`);
  return j;
}
// Live chat costs quota per check, so poll only while a broadcast is live, at most every 12 s.
async function ytChatLoop() {
  clearTimeout(yt.chatTimer); yt.chatTimer = null;
  if (!yt.chatId || !state.platforms.youtube.live) return;
  let wait = 12000;
  try {
    const q = new URLSearchParams({ liveChatId: yt.chatId, part: 'snippet,authorDetails', maxResults: '200' }); if (yt.pageToken) q.set('pageToken', yt.pageToken);
    const j = await ytApi('GET', 'liveChat/messages?' + q);
    const first = !yt.pageToken; yt.pageToken = j.nextPageToken;
    if (!first) for (const m of j.items || []) {
      const text = m.snippet?.displayMessage; if (!text) continue;
      pushChat({ platform: 'youtube', user: m.authorDetails?.displayName || '?', color: '', text, mod: !!m.authorDetails?.isChatModerator, broadcaster: !!m.authorDetails?.isChatOwner });
    }
    wait = Math.max(12000, j.pollingIntervalMillis || 0);
  } catch (e) { log('youtube chat poll failed:', e.message); wait = /quota/i.test(e.message) ? 15 * 60e3 : 30000; }
  yt.chatTimer = setTimeout(ytChatLoop, wait);
}
async function pollYoutube() {
  const id = settings.youtubeChannelId; if (!id) return;
  if (secrets.youtubeRefreshToken) {
    try {
      const pick = async (status) => (await ytApi('GET', `liveBroadcasts?part=snippet,status&broadcastStatus=${status}&broadcastType=all&maxResults=5`)).items?.[0];
      const b = (await pick('active')) || (await pick('upcoming'));
      const live = b?.status?.lifeCycleStatus === 'live';
      let viewers = 0;
      if (live) { const v = await ytApi('GET', 'videos?part=liveStreamingDetails&id=' + b.id); viewers = Number(v.items?.[0]?.liveStreamingDetails?.concurrentViewers || 0); }
      yt.broadcast = b || null;
      const newChat = live ? b.snippet?.liveChatId : null;
      if (newChat !== yt.chatId) { yt.chatId = newChat; yt.pageToken = null; }
      state.platforms.youtube = { connected: true, authorized: true, live, viewers, title: b?.snippet?.title || '', startedAt: b?.snippet?.actualStartTime || null,
        url: b ? `https://www.youtube.com/watch?v=${b.id}` : `https://www.youtube.com/channel/${id}/live`, hasBroadcast: !!b };
      if (live && !yt.chatTimer) ytChatLoop();
      return;
    } catch (e) { log('youtube api poll failed:', e.message); }
  }
  try {
    const r = await fetch(`https://www.youtube.com/channel/${id}/live`, { headers: { 'User-Agent': 'Mozilla/5.0', 'Accept-Language': 'en-US' } });
    const html = await r.text();
    const live = /"isLiveNow":true/.test(html);
    const viewers = live ? Number((html.match(/"originalViewCount":"(\d+)"/) || html.match(/"concurrentViewers":"(\d+)"/) || [])[1] || 0) : 0;
    state.platforms.youtube = { connected: true, authorized: false, canAuthorize: !!secrets.youtubeClientId, live, viewers, url: `https://www.youtube.com/channel/${id}/live`, readOnly: true };
  } catch (e) { state.platforms.youtube = { connected: false, error: e.message }; }
}
setInterval(pollTwitch, 20000); setInterval(pollKick, 30000); setInterval(pollYoutube, 60000);
pollTwitch(); pollKick(); pollYoutube(); twitchChat();

// ---------------------------------------------------------------- auth
const sessions = new Map(); // token -> expiry ms
const fails = new Map();    // ip -> { n, until }
function checkPassword(pw) {
  const [salt, hash] = cfg.passwordHash.split(':');
  const got = crypto.scryptSync(String(pw), Buffer.from(salt, 'hex'), 64);
  return crypto.timingSafeEqual(got, Buffer.from(hash, 'hex'));
}
function safeEqual(a, b) { const x = Buffer.from(String(a)), y = Buffer.from(String(b)); return x.length === y.length && crypto.timingSafeEqual(x, y); }
function cookies(req) { return Object.fromEntries((req.headers.cookie || '').split(';').map((c) => c.trim().split('=')).filter((p) => p.length === 2)); }
// One sign-in covers the dashboard and Studio: the cookie is shared by both addresses (irl.example.com and
// studio.example.com, or name.duckdns.org and studio.name.duckdns.org). "Keep me signed in" sessions renew
// themselves on every visit, so you stay signed in as long as you use it at least once every 30 days; without it,
// the session ends when the browser closes (or after 12 hours without use).
const COOKIE = '__Secure-irlhk', OLD_COOKIE = '__Host-irlhk';
const KEEP_MS = SESSION_DAYS * 864e5, SHORT_MS = 12 * 3600e3;
function cookieDomain(req) {
  const host = String(req.headers.host || '').split(':')[0].toLowerCase(), d = settings.domain, st = settings.studioDomain;
  if (!d || (host !== d && host !== st)) return '';            // localhost, LAN IP: cookie stays on this address
  if (st && st.endsWith('.' + d)) return d;                      // name.duckdns.org + studio.name.duckdns.org
  const parent = d.replace(/^[^.]+\./, '');                      // irl.example.com -> example.com
  return st && st.endsWith('.' + parent) && parent.includes('.') ? parent : '';
}
function sessionCookie(req, token, s) {
  const dom = cookieDomain(req);
  return `${COOKIE}=${token}; Path=/; Secure; HttpOnly; SameSite=Lax${dom ? `; Domain=${dom}` : ''}${s.keep ? `; Max-Age=${SESSION_DAYS * 86400}` : ''}`;
}
function clearCookies(req) {
  const dom = cookieDomain(req), gone = 'Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=0';
  return [`${COOKIE}=; ${gone}${dom ? `; Domain=${dom}` : ''}`, `${COOKIE}=; ${gone}`, `${OLD_COOKIE}=; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=0`];
}
// Returns the session token if signed in, renewing the session (and its cookie, on `res`) when it's an hour old.
function authed(req, res) {
  const c = cookies(req), t = c[COOKIE] || c[OLD_COOKIE]; if (!t) return null;
  const s = sessions.get(t);
  if (!s || s.exp < Date.now()) { sessions.delete(t); return null; }
  const now = Date.now(), life = s.keep ? KEEP_MS : SHORT_MS;
  if (res && (now - (s.renewed || 0) > 3600e3 || !c[COOKIE])) {
    s.exp = now + life; s.renewed = now; saveSessions();
    res.setHeader('Set-Cookie', c[COOKIE] ? [sessionCookie(req, t, s)] : [sessionCookie(req, t, s), `${OLD_COOKIE}=; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=0`]);
  }
  return t;
}
function clientIp(req) { return (req.headers['x-forwarded-for'] || '').split(',')[0].trim() || req.socket.remoteAddress; }
function saveSessions() { fs.writeFile(path.join(DIR, 'sessions.json'), JSON.stringify([...sessions]), () => {}); }
try {
  for (const [t, v] of JSON.parse(fs.readFileSync(path.join(DIR, 'sessions.json'), 'utf8'))) {
    const s = typeof v === 'number' ? { exp: v, keep: true, renewed: 0 } : v;   // sessions saved by older versions were 30-day ones
    if (s.exp > Date.now()) sessions.set(t, s);
  }
} catch { }
// Set-DashboardLogin.ps1 rewrites config.json; pick up the new login and sign every device out.
fs.watchFile(CONFIG_FILE, { interval: 2000 }, () => {
  let next; try { next = readJson(CONFIG_FILE); } catch { return; }
  if (!next.username || !next.passwordHash) return;
  if (next.username === cfg.username && next.passwordHash === cfg.passwordHash) return;
  cfg = { ...cfg, username: next.username, passwordHash: next.passwordHash };
  sessions.clear(); saveSessions(); fails.clear();
  for (const c of clients) c.end(); // open pages notice and go back to the sign-in screen
  log('login changed; all devices signed out');
});

// ---------------------------------------------------------------- actions
const SERVICE_EXE = { 'go-irl': 'go-irl.exe', mediamtx: 'mediamtx.exe', noalbs: 'noalbs.exe', caddy: 'caddy.exe' };
async function action(body) {
  switch (body.action) {
    case 'startStream': return obs.req('StartStream');
    case 'stopStream': return obs.req('StopStream');
    case 'startRecord': return obs.req('StartRecord');
    case 'stopRecord': return obs.req('StopRecord');
    case 'setScene':
      if (!state.scenes.includes(body.scene)) throw new Error('unknown scene');
      return obs.req('SetCurrentProgramScene', { sceneName: body.scene });
    case 'toggleMute':
      if (!state.inputs.some((i) => i.name === body.input)) throw new Error('unknown input');
      return obs.req('ToggleInputMute', { inputName: body.input });
    case 'refreshOverlays':
      for (const n of settings.overlayInputs || []) await obs.req('PressInputPropertiesButton', { inputName: n, propertyName: 'refreshnocache' }).catch(() => {});
      return {};
    case 'restartPhoneFeed':
      for (const n of settings.phoneInputs || []) await reopenInput(n);
      return {};
    case 'twitchChat': {
      const text = String(body.text || '').trim().slice(0, 500);
      if (!text) throw new Error('EMPTY_MESSAGE');
      if (!tw.chat || tw.chat.readyState !== 1) throw new Error('TWITCH_CHAT_DOWN');
      tw.chat.send(`PRIVMSG #${tw.login} :${text}`);
      pushChat({ platform: 'twitch', user: tw.login, color: '', text, broadcaster: true, self: true });
      return {};
    }
    case 'youtubeChat': {
      const text = String(body.text || '').trim().slice(0, 200);
      if (!text) throw new Error('EMPTY_MESSAGE');
      if (!yt.chatId) throw new Error('YOUTUBE_NOT_LIVE');
      await ytApi('POST', 'liveChat/messages?part=snippet', { snippet: { liveChatId: yt.chatId, type: 'textMessageEvent', textMessageDetails: { messageText: text } } });
      return {};
    }
    case 'kickChat': {
      const text = String(body.text || '').trim().slice(0, 500);
      if (!text) throw new Error('EMPTY_MESSAGE');
      await kickApi('POST', 'chat', { type: 'user', content: text, broadcaster_user_id: secrets.kickUserId });
      return {};
    }
    case 'setTitle': {
      const title = String(body.title || '').trim();
      if (!title || title.length > 140) throw new Error('TITLE_LENGTH');
      const done = [], failed = [];
      await helix('PATCH', 'channels?broadcaster_id=' + tw.user, { title }).then(() => done.push('Twitch'), (e) => failed.push('Twitch (' + e.message + ')'));
      if (secrets.kickRefreshToken) await kickApi('PATCH', 'channels', { stream_title: title }).then(() => { done.push('Kick'); rememberKick({ title }); }, (e) => failed.push('Kick (' + e.message + ')'));
      if (secrets.youtubeRefreshToken) {
        const b = yt.broadcast;
        if (!b) failed.push('YouTube (no live or upcoming broadcast to rename yet; it appears once OBS starts sending)');
        else await ytApi('PUT', 'liveBroadcasts?part=snippet', { id: b.id, snippet: { title, description: b.snippet.description || '', scheduledStartTime: b.snippet.scheduledStartTime } })
          .then(() => done.push('YouTube'), (e) => failed.push('YouTube (' + e.message + ')'));
      }
      await Promise.all([pollTwitch(), pollKick(), pollYoutube()]);
      if (!done.length) throw new Error(failed.join('; '));
      return { note: 'Updated on ' + done.join(' and ') + '.' + (failed.length ? ' Failed: ' + failed.join('; ') : '') };
    }
    case 'searchCategory': {
      const q = String(body.query || '').trim(); if (q.length < 2) return { results: [] };
      const r = await helix('GET', 'search/categories?first=8&query=' + encodeURIComponent(q));
      return { results: (r.data || []).map((c) => ({ id: c.id, name: c.name, art: c.box_art_url })) };
    }
    case 'setCategory': {
      if (!/^\d+$/.test(String(body.id))) throw new Error('unknown category');
      const name = String(body.name || '');
      const done = [], failed = []; let kickSuggestions;
      await helix('PATCH', 'channels?broadcaster_id=' + tw.user, { game_id: String(body.id) }).then(() => done.push('Twitch'), (e) => failed.push('Twitch (' + e.message + ')'));
      if (secrets.kickRefreshToken && name) {
        // Kick has its own category list with slightly different names (Twitch "Counter-Strike 1.6" is Kick
        // "Counter-Strike: 1.6"), so compare names without punctuation or case.
        try {
          const norm = (x) => String(x).toLowerCase().replace(/[^a-z0-9]/g, '');
          const r = await kickApi('GET', 'categories?q=' + encodeURIComponent(name));
          const match = (r.data || []).find((c) => norm(c.name) === norm(name));
          if (match) { await kickApi('PATCH', 'channels', { category_id: match.id }); rememberKick({ category: match.name }); done.push(match.name === name ? 'Kick' : `Kick (as "${match.name}")`); }
          else { kickSuggestions = (r.data || []).slice(0, 6).map((c) => ({ id: c.id, name: c.name })); failed.push('Kick'); }
        } catch (e) { failed.push('Kick (' + e.message + ')'); }
      }
      await Promise.all([pollTwitch(), pollKick()]);
      if (!done.length) throw new Error(failed.join('; '));
      return { note: 'Category updated on ' + done.join(' and ') + '.' + (kickSuggestions ? ' Kick has no category with that exact name; pick one below.' : failed.length ? ' Not changed: ' + failed.join('; ') : ''), kickSuggestions };
    }
    case 'setKickCategory': {
      if (!/^\d+$/.test(String(body.id))) throw new Error('unknown category');
      await kickApi('PATCH', 'channels', { category_id: Number(body.id) });
      if (body.name) rememberKick({ category: String(body.name) });
      await pollKick();
      return { note: 'Kick category updated.' };
    }
    case 'updateScenes': {
      if (state.stream.active || state.record.active) throw new Error('SCENES_WHILE_LIVE');
      const out = await new Promise((resolve, reject) => execFile('powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(ROOT, 'scripts', 'Update-IRLScenes.ps1')],
        { windowsHide: true, timeout: 90000 }, (err, stdout, stderr) => err ? reject(new Error((stderr || err.message).split(/\r?\n/).find((l) => l.trim()) || 'failed')) : resolve(stdout)));
      return { note: `Rebuilt from "${settings.baseCollection}". A backup of the old version was saved on the PC.`, log: out.slice(-400) };
    }
    case 'setFps': {
      const fps = Number(body.fps);
      if (![30, 60].includes(fps)) throw new Error('unknown frame rate');
      if (state.stream.active || state.record.active) throw new Error('FPS_WHILE_LIVE');
      await obs.req('SetVideoSettings', { fpsNumerator: fps, fpsDenominator: 1 });
      state.video.fps = fps;
      return {};
    }
    case 'setPlatform': {
      const p = body.platform, on = !!body.on, name = PLATFORM_NAMES[p];
      if (!name) throw new Error('unknown platform');
      const ep = endpoints();
      if (on && !ep[p]) throw new Error(`${name} has no stream key yet. Add it on the PC in the IRL Homekit OBS: ${p === 'twitch' ? 'Settings > Stream' : 'Docks > Multiple output > ' + name}.`);
      if (!on && !PLATFORMS.some((x) => x !== p && settings.streamTo[x] && ep[x])) throw new Error('Keep at least one platform on, or the stream has nowhere to go.');
      const live = (await obs.req('GetStreamStatus')).outputActive;
      if (live) {
        const primary = primaryPlatform(ep);
        if (p === primary && !on) throw new Error(`${name} carries the main stream right now. End the stream to turn it off.`);
        if (p === 'twitch' && on) throw new Error('Twitch can only be added before you go live. It will be on for the next stream.');
        settings.streamTo[p] = on; saveSettings();
        if (on) await startExtras(); else await stopExtra(p);
        platformState();
        return { note: on ? `${name} is going live now.` : `${name} stopped. The other platforms keep streaming.` };
      }
      settings.streamTo[p] = on; saveSettings();
      await applyMainOutput();
      platformState();
      const list = PLATFORMS.filter((x) => settings.streamTo[x] && ep[x]).map((x) => PLATFORM_NAMES[x]);
      return { note: `Next stream goes to ${list.join(', ')}.` };
    }
    case 'installUpdate': {
      if (!state.update) throw new Error('IRL Homekit is already up to date');
      if (state.stream?.active || state.record?.active) throw new Error('You are live or recording. End the stream first, then update.');
      // Runs on its own: the installer closes IRL Homekit (and this dashboard), updates it and reopens it.
      const child = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', path.join(ROOT, 'scripts', 'Update-IRLHomekit.ps1'), '-Yes'],
        { detached: true, stdio: 'ignore', windowsHide: true });
      child.unref();
      return { note: `Updating to ${state.update.latest}. IRL Homekit closes and reopens in about 2 minutes; this page reconnects by itself.` };
    }
    case 'setAutoStart': {
      const script = path.join(ROOT, 'scripts', 'Install-Shortcuts.ps1');
      await new Promise((resolve, reject) => execFile('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, '-AutoStart', body.on ? 'On' : 'Off', '-OnlyAutoStart'],
        { windowsHide: true, timeout: 30000 }, (err, stdout, stderr) => err ? reject(new Error((stderr || err.message).split(/\r?\n/).find((l) => l.trim()) || 'failed')) : resolve()));
      await readAutoStart();
      return { note: state.autoStart ? 'IRL Homekit opens when the PC signs in.' : 'IRL Homekit stays closed after a restart until someone opens it.' };
    }
    case 'restartService': {
      if (body.service === 'relay') {   // a Windows service, not a program the watchdog starts (the dashboard runs as admin)
        await new Promise((res, rej) => execFile('powershell.exe', ['-NoProfile', '-Command', "Restart-Service -Name 'WireGuardTunnel$irlhk' -Force"],
          { windowsHide: true }, (err) => (err ? rej(new Error('Couldn\'t restart the relay tunnel')) : res())));
        setTimeout(pollRelay, 5000);
        return { note: 'the relay tunnel reconnects within a few seconds' };
      }
      const exe = SERVICE_EXE[body.service]; if (!exe) throw new Error('unknown service');
      await new Promise((res) => execFile('taskkill', ['/IM', exe, '/F'], { windowsHide: true }, () => res()));
      return { note: 'watchdog restarts it within ~10 s' };
    }
    default: throw new Error('unknown action');
  }
}

async function relayIp() {
  const h = settings.relayHost || '';
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(h)) return h;
  const resolver = new dns.Resolver(); resolver.setServers(['1.1.1.1', '8.8.8.8']);
  return (await resolver.resolve4(h).catch(() => []))[0] || '';
}

// ---------------------------------------------------------------- phone settings (what to type into IRL Pro)
// Same address the personal phone guide uses: the DuckDNS name if there is one (it follows the home IP, or the
// relay), else the relay server if there is one (docs/RELAY.md), else the home IP as it is right now. Read from disk on every request: the remote-dashboard setup can add DuckDNS later.
// Only sent on request (never in the live /events stream), because it holds the stream passwords.
async function phoneSettings() {
  const sec = readJson(`${ROOT}/secrets.json`), set = readJson(`${ROOT}/settings.json`);
  const duck = set.duckdnsName && sec.duckdnsToken ? `${set.duckdnsName}.duckdns.org` : '';
  const relay = set.relayHost || '';
  let ip = '';
  if (!duck && !relay) { try { ip = (await (await fetch('https://api.ipify.org', { signal: AbortSignal.timeout(5000) })).text()).trim(); } catch { } }
  if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(ip)) ip = '';
  const host = duck || relay || ip || sec.publicIp || '';
  const user = sec.mediamtxUser || 'irl', pass = sec.mediamtxPass || '', phrase = sec.goirlPassphrase || '';
  return {
    host, duckdns: !!duck, relay: !!relay,
    ipChanged: !duck && !relay && !!ip && !!sec.publicIp && ip !== sec.publicIp, installIp: sec.publicIp || '',
    bonded: { server: `srtla://${host}:5000`, passphrase: phrase, combined: `srtla://${host}:5000?passphrase=${phrase}` },
    srt: { server: `srt://${host}:8890`, streamId: `publish:live:${user}:${pass}` },
    rtmp: { url: `rtmp://${host}:1935/live?user=${user}&pass=${pass}` },
  };
}

// ---------------------------------------------------------------- http
const clients = new Set();
const STATIC = { '/app.js': 'application/javascript', '/studio.js': 'application/javascript', '/style.css': 'text/css', '/icon.svg': 'image/svg+xml', '/manifest.json': 'application/manifest+json',
  '/apple-touch-icon.png': 'image/png', '/icon-192.png': 'image/png', '/icon-512.png': 'image/png', '/fonts/InterVariable.woff2': 'font/woff2' };
const IMMUTABLE = new Set(['/fonts/InterVariable.woff2']);
const SEC_HEADERS = {
  'Content-Security-Policy': "default-src 'self'; img-src 'self' blob: data:; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
  'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', 'X-Frame-Options': 'DENY', 'Cache-Control': 'no-store',
};
function send(res, code, type, body, extra = {}) { res.writeHead(code, { 'Content-Type': type, ...SEC_HEADERS, ...extra }); res.end(body); }
function readBody(req, limit = 4096) {
  return new Promise((resolve, reject) => { let b = ''; req.on('data', (c) => { b += c; if (b.length > limit) { reject(new Error('too big')); req.destroy(); } }); req.on('end', () => resolve(b)); });
}
const page = (f) => fs.readFileSync(path.join(DIR, 'public', f));
function publicState() { const { _sb, ...s } = state; s.updated = Date.now(); s.previewAt = previewAt; return s; }

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  try {
    if (STATIC[url.pathname]) return send(res, 200, STATIC[url.pathname], page(url.pathname.slice(1)), { 'Cache-Control': IMMUTABLE.has(url.pathname) ? 'public, max-age=31536000, immutable' : 'no-cache' });

    // Public pages required by Google/Kick app listings (no sign-in needed, no personal data).
    if (url.pathname === '/about' || url.pathname === '/privacy') return send(res, 200, 'text/html; charset=utf-8', page('privacy.html'), { 'Cache-Control': 'public, max-age=3600' });
    if (url.pathname === '/login' && req.method === 'GET') return send(res, 200, 'text/html; charset=utf-8', page('login.html'));
    if (url.pathname === '/login' && req.method === 'POST') {
      const ip = clientIp(req); const f = fails.get(ip) || { n: 0, until: 0 };
      const form = new URLSearchParams(await readBody(req));
      const nextQ = form.get('next') === '/studio' ? '&next=/studio' : '';
      if (f.until > Date.now()) return send(res, 303, 'text/plain', '', { Location: '/login?e=locked' + nextQ });
      const ok = safeEqual(form.get('username') || '', cfg.username) & checkPassword(form.get('password') || '');
      if (!ok) {
        f.n++; if (f.n >= 5) { f.until = Date.now() + 15 * 60e3; f.n = 0; }
        fails.set(ip, f); log('login failed from', ip);
        await new Promise((r) => setTimeout(r, 800));
        return send(res, 303, 'text/plain', '', { Location: '/login?e=1' + nextQ });
      }
      fails.delete(ip);
      const token = crypto.randomBytes(32).toString('hex');
      const keep = form.get('keep') !== null;   // "Keep me signed in" (ticked by default)
      const s = { exp: Date.now() + (keep ? KEEP_MS : SHORT_MS), keep, renewed: Date.now() };
      sessions.set(token, s); saveSessions(); log('login ok from', ip, keep ? '(kept signed in)' : '(this browser session)');
      // Back to the page they came from (dashboard or Studio), never to another site.
      const next = /^\/(studio)?$/.test(form.get('next') || '') ? form.get('next') : '/';
      return send(res, 303, 'text/plain', '', { Location: next, 'Set-Cookie': [sessionCookie(req, token, s), `${OLD_COOKIE}=; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=0`] });
    }
    if (url.pathname === '/logout') {
      const c = cookies(req); sessions.delete(c[COOKIE]); sessions.delete(c[OLD_COOKIE]); saveSessions();
      return send(res, 303, 'text/plain', '', { Location: '/login', 'Set-Cookie': clearCookies(req) });
    }

    // Kick webhooks: no session, but every message must carry a valid Kick signature.
    if (url.pathname === '/webhooks/kick' && req.method === 'POST') {
      const raw = await readBody(req, 65536);
      let ok = false; try { ok = await kickVerify(req.headers, raw); } catch (e) { log('kick verify error', e.message); }
      if (!ok) { log('kick webhook rejected (bad signature)'); return send(res, 401, 'text/plain', 'bad signature'); }
      send(res, 200, 'text/plain', 'ok');
      const id = req.headers['kick-event-message-id']; if (kickSeen.has(id)) return; kickSeen.add(id); if (kickSeen.size > 2000) kickSeen.clear();
      const ev = JSON.parse(raw); const type = req.headers['kick-event-type'];
      if (type === 'chat.message.sent') {
        const badges = (ev.sender?.identity?.badges || []).map((b) => b.type);
        pushChat({ platform: 'kick', user: ev.sender?.username || '?', color: ev.sender?.identity?.username_color || '',
          text: String(ev.content || '').replace(/\[emote:\d+:([^\]]+)\]/g, ':$1:'), mod: badges.includes('moderator'), broadcaster: badges.includes('broadcaster') });
      } else if (type === 'livestream.status.updated') { pollKick(); }
      return;
    }
    // YouTube (Google) sign-in callback, same one-time-state protection as Kick.
    if (url.pathname === '/oauth/youtube/callback') {
      const st = oauthStates.get(url.searchParams.get('state') || ''); oauthStates.delete(url.searchParams.get('state') || '');
      const back = (msg) => send(res, 303, 'text/plain', '', { Location: '/studio?youtube=' + encodeURIComponent(msg) });
      if (!st || st.exp < Date.now()) return back('expired');
      if (url.searchParams.get('error')) return back('denied');
      const r = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ grant_type: 'authorization_code', code: url.searchParams.get('code') || '', client_id: secrets.youtubeClientId,
          client_secret: secrets.youtubeClientSecret, redirect_uri: ytRedirect(), code_verifier: st.verifier }) });
      const j = await r.json().catch(() => ({}));
      if (!r.ok || !j.access_token || !j.refresh_token) { log('youtube token exchange failed', r.status, j.error, j.error_description); return back('failed'); }
      saveSecrets({ youtubeAccessToken: j.access_token, youtubeRefreshToken: j.refresh_token, youtubeExpiresAt: Date.now() + (j.expires_in || 3600) * 1000 });
      log('youtube connected');
      pollYoutube();
      return back('connected');
    }
    // Kick sign-in callback: the session cookie isn't sent on this cross-site redirect, so the one-time state proves it's ours.
    if (url.pathname === '/oauth/kick/callback') {
      const st = oauthStates.get(url.searchParams.get('state') || ''); oauthStates.delete(url.searchParams.get('state') || '');
      const back = (msg) => send(res, 303, 'text/plain', '', { Location: '/studio?kick=' + encodeURIComponent(msg) });
      if (!st || st.exp < Date.now()) return back('expired');
      if (url.searchParams.get('error')) return back('denied');
      const r = await fetch('https://id.kick.com/oauth/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ grant_type: 'authorization_code', code: url.searchParams.get('code') || '', client_id: secrets.kickClientId,
          client_secret: secrets.kickClientSecret, redirect_uri: kickRedirect(), code_verifier: st.verifier }) });
      const j = await r.json().catch(() => ({}));
      if (!r.ok || !j.access_token) { log('kick token exchange failed', r.status, JSON.stringify(j).slice(0, 200)); return back('failed'); }
      saveSecrets({ kickAccessToken: j.access_token, kickRefreshToken: j.refresh_token, kickExpiresAt: Date.now() + (j.expires_in || 3600) * 1000 });
      try { await kickAfterLogin(); } catch (e) { log('kick setup after login failed', e.message); }
      pollKick();
      return back('connected');
    }

    if (!authed(req, res)) {
      if (url.pathname.startsWith('/api') || url.pathname === '/events' || url.pathname === '/preview.jpg') return send(res, 401, 'text/plain', 'login required');
      return send(res, 303, 'text/plain', '', { Location: url.pathname === '/studio' ? '/login?next=/studio' : '/login' });
    }

    if (url.pathname === '/oauth/kick/start') {
      if (!secrets.kickClientId || !secrets.kickClientSecret) return send(res, 303, 'text/plain', '', { Location: '/studio?kick=noapp' });
      const verifier = crypto.randomBytes(48).toString('base64url');
      const stateId = crypto.randomBytes(24).toString('base64url');
      oauthStates.set(stateId, { verifier, exp: Date.now() + 10 * 60e3 });
      const q = new URLSearchParams({ client_id: secrets.kickClientId, response_type: 'code', redirect_uri: kickRedirect(), state: stateId, scope: KICK_SCOPES,
        code_challenge: crypto.createHash('sha256').update(verifier).digest('base64url'), code_challenge_method: 'S256' });
      return send(res, 303, 'text/plain', '', { Location: 'https://id.kick.com/oauth/authorize?' + q });
    }
    if (url.pathname === '/oauth/youtube/start') {
      if (!secrets.youtubeClientId || !secrets.youtubeClientSecret) return send(res, 303, 'text/plain', '', { Location: '/studio?youtube=noapp' });
      const verifier = crypto.randomBytes(48).toString('base64url');
      const stateId = crypto.randomBytes(24).toString('base64url');
      oauthStates.set(stateId, { verifier, exp: Date.now() + 10 * 60e3 });
      const q = new URLSearchParams({ client_id: secrets.youtubeClientId, redirect_uri: ytRedirect(), response_type: 'code', scope: YT_SCOPE,
        access_type: 'offline', prompt: 'consent', include_granted_scopes: 'true', state: stateId,
        code_challenge: crypto.createHash('sha256').update(verifier).digest('base64url'), code_challenge_method: 'S256' });
      return send(res, 303, 'text/plain', '', { Location: 'https://accounts.google.com/o/oauth2/v2/auth?' + q });
    }
    const studio = url.pathname === '/studio' || (url.pathname === '/' && /^studio\./i.test(req.headers.host || ''));
    if (studio) return send(res, 200, 'text/html; charset=utf-8', page('studio.html'));
    if (url.pathname === '/') return send(res, 200, 'text/html; charset=utf-8', page('index.html'));
    if (url.pathname === '/preview.jpg') return preview ? send(res, 200, 'image/jpeg', preview) : send(res, 404, 'text/plain', 'no preview');
    if (url.pathname === '/events') {
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
      let lastChat = Math.max(0, chatSeq - 100);   // new viewers get the last 100 chat messages, then only new ones
      const tick = () => {
        const msgs = chat.filter((m) => m.id > lastChat); if (msgs.length) lastChat = msgs[msgs.length - 1].id;
        res.write(`data: ${JSON.stringify({ ...publicState(), chat: msgs })}\n\n`);
      };
      tick(); const iv = setInterval(tick, 1000); clients.add(res);
      req.on('close', () => { clearInterval(iv); clients.delete(res); });
      return;
    }
    if (url.pathname === '/api/phone' && req.method === 'GET') {
      if (req.headers['x-irlhk'] !== '1') return send(res, 403, 'text/plain', 'bad request');
      log('phone settings shown to', clientIp(req));
      return send(res, 200, 'application/json', JSON.stringify(await phoneSettings()));
    }
    if (url.pathname === '/api/action' && req.method === 'POST') {
      if (req.headers['x-irlhk'] !== '1') return send(res, 403, 'text/plain', 'bad request');
      const body = JSON.parse(await readBody(req));
      log('action', JSON.stringify(body), 'from', clientIp(req));
      try { const r = await action(body); return send(res, 200, 'application/json', JSON.stringify({ ok: true, ...r })); }
      catch (e) { return send(res, 400, 'application/json', JSON.stringify({ ok: false, error: e.message })); }
    }
    send(res, 404, 'text/plain', 'not found');
  } catch (e) { log('error', e.message); if (!res.headersSent) send(res, 500, 'text/plain', 'error'); }
});
server.listen(PORT, '127.0.0.1', () => log(`IRL Homekit dashboard on http://127.0.0.1:${PORT}`));
