// IRL Homekit full-screen scenes: animated night sky (or a GIF), channel name, custom text and a clock.
// Settings come from config.js (written by the installer) and can be overridden per OBS source with
// ?title=...&sub=...&channel=...&bg=stars|mesh|<gif url>
(function () {
  const cfg = window.IRLHK || {};
  const q = new URLSearchParams(location.search);
  const set = (id, v) => { const e = document.getElementById(id); if (e && v) e.textContent = v; };
  set('channel', q.get('channel') || cfg.channel || '');
  set('title', q.get('title'));
  set('sub', q.get('sub'));
  if (!(q.get('channel') || cfg.channel)) document.querySelector('.footer .chip')?.remove();
  const clock = document.getElementById('clock');
  const tick = () => { if (clock) clock.textContent = new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }); };
  tick(); setInterval(tick, 10000);

  // ---- background
  const bg = q.get('bg') || cfg.background || 'stars';
  if (/^https?:|^file:|\.(gif|webp|mp4)$/i.test(bg)) {
    document.body.classList.add('bg-media');
    const isVideo = /\.mp4($|\?)/i.test(bg);
    const m = document.createElement(isVideo ? 'video' : 'img');
    m.className = 'bg-media-el'; m.src = bg;
    if (isVideo) { m.autoplay = true; m.loop = true; m.muted = true; m.playsInline = true; }
    m.onerror = () => { document.body.classList.remove('bg-media'); m.remove(); startStars(); };
    document.body.prepend(m);
    return;
  }
  if (bg === 'mesh') return;           // just the coloured mesh from screen.css
  startStars();

  // Night sky: three depth layers of twinkling stars drifting slowly, a faint milky-way band,
  // and an occasional shooting star. Drawn on a canvas so it stays sharp at 1080p.
  function startStars() {
    document.body.classList.add('bg-stars');
    const c = document.createElement('canvas'); c.className = 'stars';
    c.width = 1920; c.height = 1080; document.body.prepend(c);
    const ctx = c.getContext('2d');
    const rand = (a, b) => a + Math.random() * (b - a);
    const layers = [ { n: 520, r: [0.4, 1.1], v: 0.6 }, { n: 220, r: [0.9, 1.8], v: 1.4 }, { n: 70, r: [1.6, 2.6], v: 2.6 } ];
    const stars = [];
    for (const L of layers) for (let i = 0; i < L.n; i++) {
      // bias some stars into a diagonal band for a milky-way feel
      const band = Math.random() < 0.35;
      let x = rand(0, 1920), y = rand(0, 1080);
      if (band) { const t = rand(-0.1, 1.1); x = t * 1920 + rand(-160, 160); y = 1080 - t * 1080 * 0.9 + rand(-140, 140); }
      stars.push({ x, y, r: rand(...L.r), v: L.v, tw: rand(0, Math.PI * 2), ts: rand(0.6, 2.2), hue: Math.random() < 0.15 ? rand(190, 230) : (Math.random() < 0.1 ? rand(20, 45) : 0) });
    }
    const shooters = [];
    let last = performance.now();
    function frame(now) {
      const dt = Math.min(50, now - last) / 1000; last = now;
      ctx.clearRect(0, 0, 1920, 1080);
      // milky way glow
      const g = ctx.createLinearGradient(0, 1080, 1920, 120);
      g.addColorStop(0, 'rgba(120,90,255,0)'); g.addColorStop(.45, 'rgba(150,120,255,.10)'); g.addColorStop(.55, 'rgba(255,120,170,.08)'); g.addColorStop(1, 'rgba(120,90,255,0)');
      ctx.fillStyle = g; ctx.fillRect(0, 0, 1920, 1080);
      for (const s of stars) {
        s.x += s.v * dt * 4; if (s.x > 1925) s.x = -5;
        s.tw += s.ts * dt;
        const a = 0.35 + 0.65 * (0.5 + 0.5 * Math.sin(s.tw));
        ctx.beginPath(); ctx.arc(s.x, s.y, s.r, 0, Math.PI * 2);
        ctx.fillStyle = s.hue ? `hsla(${s.hue},80%,85%,${a})` : `rgba(255,255,255,${a})`; ctx.fill();
        if (s.r > 1.9) { ctx.globalAlpha = a * 0.25; ctx.beginPath(); ctx.arc(s.x, s.y, s.r * 3.2, 0, Math.PI * 2); ctx.fill(); ctx.globalAlpha = 1; }
      }
      if (Math.random() < dt * 0.22) shooters.push({ x: rand(200, 1800), y: rand(-40, 420), vx: rand(-900, -600), vy: rand(300, 480), life: 0 });
      for (let i = shooters.length - 1; i >= 0; i--) {
        const s = shooters[i]; s.life += dt; s.x += s.vx * dt; s.y += s.vy * dt;
        const fade = Math.max(0, 1 - s.life / 1.1);
        const tail = ctx.createLinearGradient(s.x, s.y, s.x - s.vx * 0.18, s.y - s.vy * 0.18);
        tail.addColorStop(0, `rgba(255,255,255,${0.95 * fade})`); tail.addColorStop(1, 'rgba(255,255,255,0)');
        ctx.strokeStyle = tail; ctx.lineWidth = 2.4; ctx.lineCap = 'round';
        ctx.beginPath(); ctx.moveTo(s.x, s.y); ctx.lineTo(s.x - s.vx * 0.18, s.y - s.vy * 0.18); ctx.stroke();
        if (s.life > 1.2) shooters.splice(i, 1);
      }
      requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
  }
})();
