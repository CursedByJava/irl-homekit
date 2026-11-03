'use strict';
const $ = (id) => document.getElementById(id);
const PLATFORM = { twitch: { name: 'Twitch', color: '#a970ff' }, kick: { name: 'Kick', color: '#53fc18' }, youtube: { name: 'YouTube', color: '#ff4e45' } };
let s = null; let lastMsg = 0; let filter = 'all'; let titleDirty = false;
const messages = [];
if (location.hostname.startsWith('studio.')) document.querySelector('[data-stream]').href = 'https://' + location.hostname.replace(/^studio\./, 'irl.') + '/';

function el(tag, cls, text) { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
let toastTimer;
function toast(kind, title, why) {
  const t = $('toast'); t.className = 'toast show ' + kind; t.replaceChildren(el('b', '', title)); if (why) t.append(el('span', 'why', why));
  clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove('show'), kind === 'error' ? 9000 : 4000);
}
function explain(action, msg) {
  msg = String(msg || '');
  if (/401|login required/i.test(msg)) return ['You were signed out.', 'Sign in again to keep going.'];
  if (/Failed to fetch|NetworkError/i.test(msg)) return ['Couldn\'t reach your home PC.', 'Your phone or home internet dropped for a moment. Try again.'];
  if (/TITLE_LENGTH/.test(msg)) return ['Title needs 1–140 characters.', 'Twitch doesn\'t allow empty titles or more than 140 characters.'];
  if (/EMPTY_MESSAGE/.test(msg)) return ['Type a message first.', ''];
  if (/TWITCH_CHAT_DOWN/.test(msg)) return ['Twitch chat is reconnecting.', 'The connection to Twitch chat dropped. It reconnects by itself within a few seconds. Try again then.'];
  if (/Twitch 401/.test(msg)) return ['Twitch rejected the login.', 'The Twitch token was revoked or expired. Sign in again: on the PC, Start menu > IRL Homekit - Connect Twitch.'];
  if (/Twitch 403/.test(msg)) return ['Twitch says that\'s not allowed.', 'The token is missing a permission. Sign in again (on the PC, Start menu > IRL Homekit - Connect Twitch) and approve every permission.'];
  if (/YOUTUBE_NOT_CONNECTED/.test(msg)) return ['YouTube isn\'t connected.', 'Tap Connect next to YouTube under "Your channels" and approve the Google sign-in.'];
  if (/YOUTUBE_NOT_LIVE/.test(msg)) return ['YouTube chat opens when you\'re live.', 'YouTube only has a chat while a broadcast is live. Go live first, then send.'];
  if (/YouTube 403: (quotaExceeded|dailyLimitExceeded)/.test(msg)) return ['YouTube\'s daily limit is used up.', 'Google allows a fixed number of requests per day. YouTube chat and title changes come back after midnight Pacific time.'];
  if (/YouTube 401/.test(msg)) return ['YouTube signed you out.', 'The Google sign-in expired or was removed. Tap Connect next to YouTube again.'];
  if (/KICK_NOT_CONNECTED/.test(msg)) return ['Kick isn\'t connected.', 'Tap Connect next to Kick under "Your channels" and approve the sign-in.'];
  if (/Kick 401/.test(msg)) return ['Kick signed you out.', 'The Kick connection expired or was removed. Tap Connect next to Kick to sign in again.'];
  if (/Kick 429/.test(msg)) return ['Slow down a little.', 'Kick limits how often this can happen. Wait a minute and try again.'];
  if (/Twitch 429/.test(msg)) return ['Slow down a little.', 'Twitch limits how often this can change. Wait a minute and try again.'];
  return ['That didn\'t work.', 'The PC said: "' + msg + '". Try again.'];
}
async function act(body, okTitle, okWhy) {
  try {
    const r = await fetch('/api/action', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-IRLHK': '1' }, body: JSON.stringify(body), credentials: 'same-origin' });
    if (r.status === 401) { location.href = '/login'; return null; }
    const j = await r.json().catch(() => ({ ok: false, error: 'HTTP ' + r.status }));
    if (!j.ok) { const [t, w] = explain(body.action, j.error); toast('error', t, w); return null; }
    if (okTitle) toast('success', okTitle, okWhy || j.note);
    return j;
  } catch (e) { const [t, w] = explain(body.action, e.message); toast('error', t, w); return null; }
}

// ---------- live data
function connect() {
  const es = new EventSource('/events', { withCredentials: true });
  es.onmessage = (ev) => { lastMsg = Date.now(); s = JSON.parse(ev.data); if (s.chat?.length) addChat(s.chat); render(); };
  es.onerror = () => { es.close(); fetch('/events', { method: 'HEAD' }).then((r) => { if (r.status === 401) location.href = '/login'; }).catch(() => {}); setTimeout(connect, 3000); };
}
setInterval(() => {
  const b = $('linkBanner');
  if (lastMsg && Date.now() - lastMsg > 5000) { b.innerHTML = '<b>Lost connection to your home PC.</b> Reconnecting… Your stream keeps running on its own.'; b.classList.add('show'); }
  else b.classList.remove('show');
}, 1000);
connect();
{
  const k = new URLSearchParams(location.search).get('kick');
  const msgs = {
    connected: ['success', 'Kick connected.', 'Title, category and chat now go to Kick too. Kick chat shows up here as people type.'],
    denied: ['error', 'Kick sign-in was cancelled.', 'Nothing changed. Tap Connect again whenever you want to link Kick.'],
    expired: ['error', 'That Kick sign-in link expired.', 'Sign-in links last 10 minutes. Tap Connect again.'],
    failed: ['error', 'Kick didn\'t accept the sign-in.', 'Kick rejected the app\'s credentials. Check the Kick developer app\'s Client ID/Secret on the PC, then try again.'],
    noapp: ['error', 'The Kick app isn\'t set up on the PC yet.', 'Add the Kick developer app\'s Client ID and Secret to secrets.json first.'],
  }[k];
  if (msgs) { toast(...msgs); history.replaceState(null, '', location.pathname); }
  const y = new URLSearchParams(location.search).get('youtube');
  const ymsgs = {
    connected: ['success', 'YouTube connected.', 'Title changes go to your YouTube broadcast too, and YouTube chat shows up here while you\'re live.'],
    denied: ['error', 'YouTube sign-in was cancelled.', 'Nothing changed. Tap Connect again whenever you want to link YouTube.'],
    expired: ['error', 'That YouTube sign-in link expired.', 'Sign-in links last 10 minutes. Tap Connect again.'],
    failed: ['error', 'Google didn\'t complete the sign-in.', 'Try Connect again. If Google showed "app not verified", choose Advanced → Go to IRL Homekit Studio.'],
    noapp: ['error', 'The YouTube app isn\'t set up on the PC yet.', 'Add the Google OAuth client ID and secret to secrets.json first.'],
  }[y];
  if (ymsgs) { toast(...ymsgs); history.replaceState(null, '', location.pathname); }
}

// ---------- render
function fmtUptime(iso) { if (!iso) return ''; const t = Math.floor((Date.now() - new Date(iso)) / 1000); const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60); return h ? `${h}h ${m}m` : `${m}m`; }
function render() {
  const p = s.platforms || {};
  const live = Object.values(p).filter((x) => x.live);
  const total = live.reduce((a, x) => a + (x.viewers || 0), 0);
  $('viewersPill').className = 'pill' + (live.length ? ' live' : '');
  const vt = $('viewersText'); vt.replaceChildren(live.length ? `LIVE · ${total.toLocaleString()}` : 'Offline');
  if (live.length) { const w = document.createElement('span'); w.className = 'wide'; w.textContent = ' watching'; vt.append(w); }   // "watching" hides on narrow phones

  $('platforms').replaceChildren(...Object.entries(PLATFORM).map(([k, meta]) => {
    const x = p[k] || {};
    const it = el('div', 'item platform');
    const dot = el('span', 'status-dot ' + (x.live ? 'bad' : x.connected ? 'ok' : ''));
    if (x.live) dot.title = 'Live';
    const g = el('div', 'grow');
    const head = el('div', 'title'); head.append(el('span', 'pname', meta.name)); head.style.setProperty('--pc', meta.color);
    let desc;
    if (x.error && !x.connected) desc = `Can't check right now (${x.error}).`;
    else if (!x.connected) desc = k === 'youtube' ? 'Add your channel to settings to see YouTube status.' : 'Not connected yet.';
    else if (x.live) desc = `Live for ${fmtUptime(x.startedAt) || 'a bit'} · ${(x.viewers || 0).toLocaleString()} watching`;
    else desc = 'Offline';
    g.append(head, el('div', 'desc', desc));
    if (x.title) g.append(el('div', 'desc ptitle', '“' + x.title + '”' + (x.category ? ' · ' + x.category : '')));
    it.append(dot, g);
    if (k !== 'twitch' && x.canAuthorize && !x.authorized) {
      const c = el('a', 'btn small go', 'Connect'); c.href = `/oauth/${k}/start`; c.title = `Sign in to ${meta.name} so Studio can change your title and chat`; it.append(c);
    } else if (x.url) { const a = el('a', 'btn small ghost', 'Open'); a.href = x.url; a.target = '_blank'; a.rel = 'noopener'; it.append(a); }
    return it;
  }));

  // where title/category/chat changes go
  const editable = ['Twitch']; if (p.kick?.authorized) editable.push('Kick'); if (p.youtube?.authorized) editable.push('YouTube');
  $('infoNote').innerHTML = 'Title updates <b>' + editable.join('</b>, <b>') + '</b>. Category updates Twitch' + (p.kick?.authorized ? ' and Kick' : '') + '.' +
    (!p.kick?.authorized || !p.youtube?.authorized ? ' Connect ' + [!p.kick?.authorized && 'Kick', !p.youtube?.authorized && 'YouTube'].filter(Boolean).join(' and ') + ' above to include ' + ((!p.kick?.authorized && !p.youtube?.authorized) ? 'them' : 'it') + '.' : '');
  const targets = [['twitch', 'Twitch']];
  if (p.kick?.authorized) targets.push(['kick', 'Kick']);
  if (p.youtube?.authorized) targets.push(['youtube', 'YouTube']);
  if (targets.length > 1) targets.push(['all', 'All']);
  const sel = $('chatTarget');
  if (sel.options.length !== targets.length) { const keep = sel.value; sel.replaceChildren(...targets.map(([v, t]) => { const o = el('option', '', t); o.value = v; return o; })); if (targets.some(([v]) => v === keep)) sel.value = keep; }

  const t = p.twitch || {};
  if (!titleDirty && t.title != null && document.activeElement !== $('titleInput')) { $('titleInput').value = t.title; updateCount(); }
  $('catCurrent').textContent = 'Current: ' + (t.category || '–');

  const login = s.meta?.twitchChannel || (t.url || '').split('/').pop();
  if (!$('links').childElementCount && login) {
    const links = [
      ['Twitch go-live notification', 'Stream Manager → Edit Stream Info → Go Live Notification.', `https://dashboard.twitch.tv/u/${login}/stream-manager`],
      ['Twitch stream key & settings', 'Latency, VOD storage, stream key.', `https://dashboard.twitch.tv/u/${login}/settings/stream`],
      ['Kick dashboard', 'Title, category, go-live notification, stream key.', 'https://dashboard.kick.com/'],
      ['YouTube Studio live', 'Title, thumbnail, made-for-kids setting, stream key.', 'https://studio.youtube.com/channel/UC/livestreaming'],
    ];
    $('links').replaceChildren(...links.map(([title, desc, href]) => {
      const it = el('div', 'item'); const g = el('div', 'grow'); g.append(el('div', 'title', title), el('div', 'desc', desc));
      const a = el('a', 'btn small ghost', 'Open'); a.href = href; a.target = '_blank'; a.rel = 'noopener'; it.append(g, a); return it;
    }));
  }
  if (location.hostname.startsWith('studio.')) $('irlLink').href = 'https://' + location.hostname.replace(/^studio\./, 'irl.') + '/';
}

// ---------- chat
const chatBox = $('chat');
function nearBottom() { return chatBox.scrollHeight - chatBox.scrollTop - chatBox.clientHeight < 60; }
function addChat(list) {
  const stick = nearBottom();
  for (const m of list) { messages.push(m); if (messages.length > 300) messages.shift(); }
  $('chatEmpty')?.remove();
  for (const m of list) if (filter === 'all' || filter === m.platform) chatBox.append(chatLine(m));
  while (chatBox.childElementCount > 300) chatBox.firstElementChild.remove();
  if (stick) chatBox.scrollTop = chatBox.scrollHeight; else $('jumpBtn').hidden = false;
}
function chatLine(m) {
  const row = el('div', 'msg' + (m.self ? ' self' : ''));
  const badge = el('span', 'pbadge ' + m.platform, PLATFORM[m.platform]?.name[0] || '?'); badge.title = PLATFORM[m.platform]?.name || '';
  const user = el('span', 'user', m.user); if (m.color) user.style.color = m.color;
  if (m.broadcaster) user.classList.add('host'); else if (m.mod) user.classList.add('mod');
  row.append(el('span', 'time', new Date(m.ts).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })), badge, user, document.createTextNode(': ' + m.text));
  return row;
}
function rerenderChat() {
  chatBox.replaceChildren(...messages.filter((m) => filter === 'all' || m.platform === filter).map(chatLine));
  if (!chatBox.childElementCount) chatBox.append(el('div', 'empty-note', filter === 'all' ? 'No messages yet.' : `No ${PLATFORM[filter].name} messages yet.` + (filter !== 'twitch' ? ' This platform\'s chat isn\'t connected yet (see "More platforms").' : '')));
  chatBox.scrollTop = chatBox.scrollHeight;
}
chatBox.addEventListener('scroll', () => { if (nearBottom()) $('jumpBtn').hidden = true; });
$('jumpBtn').onclick = () => { chatBox.scrollTop = chatBox.scrollHeight; $('jumpBtn').hidden = true; };
document.querySelectorAll('[data-filter]').forEach((b) => b.onclick = () => {
  filter = b.dataset.filter; document.querySelectorAll('[data-filter]').forEach((x) => x.classList.toggle('on', x === b)); rerenderChat();
});
$('chatForm').onsubmit = async (e) => {
  e.preventDefault(); const text = $('chatInput').value.trim(); if (!text) return;
  $('chatInput').disabled = true;
  const to = $('chatTarget').value;
  const results = [];
  const p = s?.platforms || {};
  if (to === 'twitch' || to === 'all') results.push(await act({ action: 'twitchChat', text }));
  if (to === 'kick' || (to === 'all' && p.kick?.authorized)) results.push(await act({ action: 'kickChat', text }));
  if (to === 'youtube' || (to === 'all' && p.youtube?.authorized && p.youtube?.live)) results.push(await act({ action: 'youtubeChat', text }));
  $('chatInput').disabled = false; if (results.every(Boolean)) $('chatInput').value = ''; $('chatInput').focus();
};

// ---------- title & category
function updateCount() { const n = $('titleInput').value.length; $('titleCount').textContent = `${n} / 140`; $('titleSave').disabled = !titleDirty || !n; }
$('titleInput').addEventListener('input', () => { titleDirty = $('titleInput').value !== ((s?.platforms?.twitch || {}).title || ''); updateCount(); });
$('titleSave').onclick = async () => {
  $('titleSave').disabled = true;
  const r = await act({ action: 'setTitle', title: $('titleInput').value.trim() }, 'Title updated.');
  if (r) titleDirty = false; updateCount();
};
// Kick names some categories differently; when there's no match, let the user pick Kick's version.
function showKickChoices(twitchName, list) {
  const box = $('kickCats');
  if (!list) { box.hidden = true; box.replaceChildren(); return; }
  box.hidden = false;
  const head = el('div', 'desc'); head.append(`Kick doesn't have a category called "${twitchName}". Pick the Kick category to use:`);
  const btns = list.length ? list.map((k) => {
    const b = el('button', 'cat', k.name);
    b.onclick = async () => { const r = await act({ action: 'setKickCategory', id: k.id, name: k.name }, `Kick category set to ${k.name}.`); if (r) showKickChoices(); };
    return b;
  }) : [el('div', 'empty-note', 'Kick returned no similar categories. Search for a different name above.')];
  const skip = el('button', 'btn small ghost', 'Leave Kick as it is'); skip.onclick = () => showKickChoices();
  box.replaceChildren(head, ...btns, skip);
}
let catTimer;
$('catInput').addEventListener('input', () => {
  clearTimeout(catTimer);
  const q = $('catInput').value.trim();
  if (q.length < 2) { $('catResults').replaceChildren(); return; }
  catTimer = setTimeout(async () => {
    const r = await act({ action: 'searchCategory', query: q });
    if (!r) return;
    if (!r.results.length) { $('catResults').replaceChildren(el('div', 'empty-note', `No Twitch category matches "${q}".`)); return; }
    $('catResults').replaceChildren(...r.results.map((c) => {
      const b = el('button', 'cat'); const img = el('img'); img.src = c.art.replace('{width}', '52').replace('{height}', '72'); img.alt = '';
      b.append(img, el('span', '', c.name));
      b.onclick = async () => {
        const ok = await act({ action: 'setCategory', id: c.id, name: c.name }, `Category set to ${c.name}.`);
        if (ok) { $('catInput').value = ''; $('catResults').replaceChildren(); showKickChoices(c.name, ok.kickSuggestions); }
      };
      return b;
    }));
  }, 350);
});
