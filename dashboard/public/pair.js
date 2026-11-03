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
      // No HTTPS certificate yet: a phone would open a dead link, so there's no code; say why instead (j.cert.problem,
      // from the web server's log), and keep checking until the certificate is there.
      if (j.error === 'NO_CERT') {
        $('qr').innerHTML = '';
        const why = {
          OTHER_DEVICE: 'Your router sends ports 443 and 80 to <b>another device</b> on your network (maybe another PC with IRL Homekit), not this PC ('
            + j.cert.lan + '). In your router\'s port forwarding, point TCP 443 and TCP 80 at ' + j.cert.lan + ', or delete those two rules (IRL Homekit then opens them by itself).',
          UNREACHABLE: 'The internet can\'t reach this PC on ports 443 and 80 yet (the router, or an internet connection that doesn\'t take incoming connections).'
            + ' On this PC: Start menu &gt; <b>IRL Homekit - Set up remote dashboard</b> checks it and says what to do.',
          NO_CERT: 'Your dashboard\'s free HTTPS certificate isn\'t there yet. If IRL Homekit just started, give it a minute. Otherwise, on this PC: Start menu &gt; <b>IRL Homekit - Set up remote dashboard</b> checks why.',
        }[(j.cert || {}).problem] || ('The internet can\'t reach this PC yet. Usually the router isn\'t letting ports 80 and 443 through &mdash; '
          + 'or another PC on the same network already has them, and only one can. Start menu &gt; <b>IRL Homekit - Set up remote dashboard</b> checks it.');
        $('pairSub').textContent = 'Almost there: your phone can\'t open the dashboard yet.';
        $('pairSteps').innerHTML = '<li>' + why + '</li><li>Then come back here: <a href="#" id="pairAgain">check again</a>.</li>';
        $('pairAgain').onclick = (e) => { e.preventDefault(); show(); };
        $('pairFoot').hidden = true;
        timer = setTimeout(show, 15000);   // keeps checking by itself
        return;
      }
      $('pairFoot').hidden = false;
      $('pairSteps').innerHTML = '<li>Your phone opens your IRL Homekit dashboard, already signed in.</li>'
        + '<li>Tap <b>Open in IRL Pro</b> there, and accept the import. IRL Pro is set up.</li>'
        + '<li>Tip: in the phone\'s browser menu, <b>Add to Home screen</b>, so the dashboard is one tap away.</li>';
      $('pairSub').textContent = 'Open your phone\'s camera and point it at this code. Tap the link that appears.';
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
