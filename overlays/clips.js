// IRL Homekit clips player: plays your past clips one after another, in random order, with a "be right back"
// banner on top. The dashboard turns it on for the BRB scene (Clips card); it can also be its own browser source.
// The dashboard hands it the clip list and, where the platform allows, each clip's video file; otherwise the clip
// plays in the platform's own embedded player.
(function () {
  const $ = (id) => document.getElementById(id);
  const q = new URLSearchParams(location.search);
  if (q.get('banner') === '0') $('banner').remove();
  if (q.get('title')) $('title').textContent = q.get('title');
  if (q.get('sub')) $('sub').textContent = q.get('sub');
  let queue = [], last = '', timer = 0;

  const shuffle = (a) => { for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };
  const getJson = async (u) => { const r = await fetch(u, { cache: 'no-store' }); return r.json(); };

  // Nothing to play (no clips, platform not connected, dashboard down): stay see-through and look again later.
  function idle() {
    document.body.classList.remove('playing'); $('player').replaceChildren();
    clearTimeout(timer); timer = setTimeout(next, 60000);
  }

  async function next() {
    clearTimeout(timer);
    if (!queue.length) {
      try { const j = await getJson('/overlay/clips.json'); queue = shuffle((j.clips || []).slice()); } catch { queue = []; }
      if (!queue.length) return idle();
      if (queue.length > 1 && queue[0].id === last) queue.push(queue.shift());
    }
    const c = queue.shift(); last = c.id;
    let file = null;
    try { file = (await getJson('/overlay/clips/file?id=' + encodeURIComponent(c.id))).url; } catch { }
    play(c, file);
  }

  function play(c, file) {
    const p = $('player');
    // Safety net: move on even if the player never reports the end.
    const done = (extra) => { clearTimeout(timer); timer = setTimeout(next, (c.duration + extra) * 1000); };
    if (file) {
      const v = document.createElement('video');
      v.src = file; v.autoplay = true; v.playsInline = true;
      v.onended = next;
      v.onerror = () => embed(c);
      v.onplaying = () => document.body.classList.add('playing');
      p.replaceChildren(v); done(8);
    } else embed(c);
    $('ctitle').textContent = c.title || 'Clip';
    $('cmeta').textContent = [c.by && 'Clipped by ' + c.by, c.views != null && c.views.toLocaleString() + ' views'].filter(Boolean).join(' · ');
    const cap = $('caption'); cap.classList.remove('show'); setTimeout(() => cap.classList.add('show'), 600); setTimeout(() => cap.classList.remove('show'), 7000);
  }

  function embed(c) {
    if (!c.embed) return next();
    const f = document.createElement('iframe');
    f.src = c.embed.replace('{parent}', encodeURIComponent(location.hostname));
    f.allow = 'autoplay; fullscreen';
    f.onload = () => document.body.classList.add('playing');
    $('player').replaceChildren(f);
    // Embedded players don't say when a clip ends: go by its length, plus time to load.
    clearTimeout(timer); timer = setTimeout(next, (c.duration + 3) * 1000);
  }

  next();
})();
