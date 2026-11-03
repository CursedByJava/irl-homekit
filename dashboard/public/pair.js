'use strict';
// "Connect your phone" page on the PC (http://localhost:8090/pair): a QR code with a one-time sign-in link.
(function () {
  const $ = (id) => document.getElementById(id);
  let timer = 0;
  async function show() {
    clearTimeout(timer);
    try {
      const r = await fetch('/pair/new', { method: 'POST', headers: { 'X-IRLHK': '1' } });
      const j = await r.json();
      if (j.error === 'NO_DOMAIN') {
        $('qr').innerHTML = '';
        $('pairSub').textContent = 'Your dashboard only works on this PC so far, so a phone can\'t open it yet.';
        $('pairSteps').innerHTML = '<li>On this PC: Start menu &gt; <b>IRL Homekit - Set up remote dashboard</b> (free, about 5 minutes).</li>'
          + '<li>Then open this page again: Start menu &gt; <b>IRL Homekit - Connect my phone</b>.</li>';
        $('pairFoot').hidden = true;
        return;
      }
      $('qr').innerHTML = window.irlQr(j.url);
      $('qr').title = j.url;
      timer = setTimeout(show, (j.expiresIn - 30) * 1000);   // a fresh one before this one runs out
    } catch (e) {
      $('qr').innerHTML = '<div class="empty-note">Couldn\'t make a code: ' + String(e.message || e) + '. Is IRL Homekit open?</div>';
    }
  }
  $('pairNew').onclick = (e) => { e.preventDefault(); show(); };
  show();
})();
