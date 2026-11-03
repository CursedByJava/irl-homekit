// Tiny QR code generator (ISO/IEC 18004: byte mode, error correction level M, versions 1-10, up to 213 bytes),
// so the dashboard needs no outside library. window.irlQr(text) returns an SVG string.
// Follows the structure of Project Nayuki's reference implementation (MIT).
(function () {
  // Per version (1-10), level M: [error correction codewords per block, blocks in group 1, data codewords per
  // block in group 1, blocks in group 2 (one more data codeword each)].
  const BLOCKS = [null, [10, 1, 16, 0], [16, 1, 28, 0], [26, 1, 44, 0], [18, 2, 32, 0], [24, 2, 43, 0], [16, 4, 27, 0],
    [18, 4, 31, 0], [22, 2, 38, 2], [22, 3, 36, 2], [26, 4, 43, 1]];
  const ALIGN = [null, [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]];

  const gfMul = (x, y) => { let z = 0; for (let i = 7; i >= 0; i--) { z = (z << 1) ^ ((z >>> 7) * 0x11d); z ^= ((y >>> i) & 1) * x; } return z & 0xff; };
  function rsDivisor(degree) {
    const r = new Array(degree).fill(0); r[degree - 1] = 1; let root = 1;
    for (let i = 0; i < degree; i++) {
      for (let j = 0; j < r.length; j++) { r[j] = gfMul(r[j], root); if (j + 1 < r.length) r[j] ^= r[j + 1]; }
      root = gfMul(root, 0x02);
    }
    return r;
  }
  function rsRemainder(data, div) {
    const r = div.map(() => 0);
    for (const b of data) { const f = b ^ r.shift(); r.push(0); div.forEach((c, i) => { r[i] ^= gfMul(c, f); }); }
    return r;
  }

  function encode(text) {
    const bytes = Array.from(new TextEncoder().encode(text));
    let ver = 1;
    for (; ver <= 10; ver++) {
      const [, g1, d1, g2] = BLOCKS[ver], cap = g1 * d1 + g2 * (d1 + 1);
      if (4 + (ver < 10 ? 8 : 16) + bytes.length * 8 <= cap * 8) break;
    }
    if (ver > 10) throw new Error('text too long for a QR code');
    const [ecLen, g1, d1, g2] = BLOCKS[ver], cap = g1 * d1 + g2 * (d1 + 1);
    // Bit stream: byte mode, length, data, terminator, padding.
    const bits = [];
    const put = (v, n) => { for (let i = n - 1; i >= 0; i--) bits.push((v >>> i) & 1); };
    put(4, 4); put(bytes.length, ver < 10 ? 8 : 16); bytes.forEach((b) => put(b, 8));
    put(0, Math.min(4, cap * 8 - bits.length)); while (bits.length % 8) bits.push(0);
    const data = []; for (let i = 0; i < bits.length; i += 8) data.push(parseInt(bits.slice(i, i + 8).join(''), 2));
    for (let p = 0xec; data.length < cap; p ^= 0xec ^ 0x11) data.push(p);
    // Blocks with their error correction, interleaved.
    const div = rsDivisor(ecLen), blocks = [];
    for (let b = 0, k = 0; b < g1 + g2; b++) { const n = d1 + (b >= g1 ? 1 : 0); const d = data.slice(k, k + n); k += n; blocks.push([d, rsRemainder(d, div)]); }
    const out = [];
    for (let i = 0; i <= d1; i++) blocks.forEach(([d]) => { if (i < d.length) out.push(d[i]); });
    for (let i = 0; i < ecLen; i++) blocks.forEach(([, e]) => out.push(e[i]));
    return { ver, codewords: out };
  }

  function build(ver, codewords, mask) {
    const size = ver * 4 + 17;
    const m = Array.from({ length: size }, () => new Array(size).fill(false));
    const fn = Array.from({ length: size }, () => new Array(size).fill(false));
    const set = (x, y, dark) => { m[y][x] = dark; fn[y][x] = true; };
    for (let i = 0; i < size; i++) { set(6, i, i % 2 === 0); set(i, 6, i % 2 === 0); }
    const finder = (cx, cy) => {
      for (let dy = -4; dy <= 4; dy++) for (let dx = -4; dx <= 4; dx++) {
        const x = cx + dx, y = cy + dy, d = Math.max(Math.abs(dx), Math.abs(dy));
        if (x >= 0 && x < size && y >= 0 && y < size) set(x, y, d !== 2 && d !== 4);
      }
    };
    finder(3, 3); finder(size - 4, 3); finder(3, size - 4);
    const al = ALIGN[ver], last = al.length - 1;
    for (let i = 0; i < al.length; i++) for (let j = 0; j < al.length; j++) {
      if ((i === 0 && j === 0) || (i === 0 && j === last) || (i === last && j === 0)) continue;
      for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) set(al[i] + dx, al[j] + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
    }
    // Format information (level M = 0b00) and, from version 7, version information.
    const fdata = (0 << 3) | mask; let rem = fdata;
    for (let i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
    const fbits = ((fdata << 10) | rem) ^ 0x5412, fb = (i) => ((fbits >>> i) & 1) === 1;
    for (let i = 0; i <= 5; i++) set(8, i, fb(i));
    set(8, 7, fb(6)); set(8, 8, fb(7)); set(7, 8, fb(8));
    for (let i = 9; i < 15; i++) set(14 - i, 8, fb(i));
    for (let i = 0; i < 8; i++) set(size - 1 - i, 8, fb(i));
    for (let i = 8; i < 15; i++) set(8, size - 15 + i, fb(i));
    set(8, size - 8, true);
    if (ver >= 7) {
      let r = ver; for (let i = 0; i < 12; i++) r = (r << 1) ^ ((r >>> 11) * 0x1f25);
      const vbits = (ver << 12) | r;
      for (let i = 0; i < 18; i++) { const bit = ((vbits >>> i) & 1) === 1, a = size - 11 + (i % 3), b = Math.floor(i / 3); set(a, b, bit); set(b, a, bit); }
    }
    // Data, in the zigzag order, with the mask applied.
    const maskFn = [(x, y) => (x + y) % 2 === 0, (x, y) => y % 2 === 0, (x) => x % 3 === 0, (x, y) => (x + y) % 3 === 0,
      (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0, (x, y) => ((x * y) % 2) + ((x * y) % 3) === 0,
      (x, y) => (((x * y) % 2) + ((x * y) % 3)) % 2 === 0, (x, y) => (((x + y) % 2) + ((x * y) % 3)) % 2 === 0][mask];
    let bit = 0;
    for (let right = size - 1; right >= 1; right -= 2) {
      if (right === 6) right = 5;
      for (let v = 0; v < size; v++) for (let j = 0; j < 2; j++) {
        const x = right - j, y = ((right + 1) & 2) === 0 ? size - 1 - v : v;
        if (fn[y][x]) continue;
        let dark = bit < codewords.length * 8 ? ((codewords[bit >>> 3] >>> (7 - (bit & 7))) & 1) === 1 : false;
        bit++;
        if (maskFn(x, y)) dark = !dark;
        m[y][x] = dark;
      }
    }
    return m;
  }

  // Lower is easier to scan (the standard's penalty rules).
  function penalty(m) {
    const n = m.length; let p = 0, dark = 0;
    const lines = [];
    for (let i = 0; i < n; i++) { lines.push(m[i]); lines.push(m.map((row) => row[i])); }
    for (const line of lines) {
      let run = 1;
      for (let i = 1; i <= n; i++) {
        if (i < n && line[i] === line[i - 1]) run++;
        else { if (run >= 5) p += run - 2; run = 1; }
      }
      const s = line.map((d) => (d ? '1' : '0')).join('');
      for (const pat of ['10111010000', '00001011101']) for (let k = s.indexOf(pat); k >= 0; k = s.indexOf(pat, k + 1)) p += 40;
    }
    for (let y = 0; y + 1 < n; y++) for (let x = 0; x + 1 < n; x++) {
      const c = m[y][x]; if (c === m[y][x + 1] && c === m[y + 1][x] && c === m[y + 1][x + 1]) p += 3;
    }
    m.forEach((row) => row.forEach((d) => { if (d) dark++; }));
    p += Math.floor(Math.abs(dark * 20 - n * n * 10) / (n * n)) * 10;
    return p;
  }

  // The modules (true = dark), without the quiet zone. Also used by tools/qr-bmp.mjs for Setup's picture.
  window.irlQrMatrix = function (text, forceMask) {   // forceMask: for tests only
    const { ver, codewords } = encode(text);
    let best = null, bestP = Infinity;
    for (let mask = 0; mask < 8; mask++) {
      if (forceMask != null && mask !== forceMask) continue;
      const m = build(ver, codewords, mask), p = penalty(m); if (p < bestP) { best = m; bestP = p; }
    }
    return best;
  };

  window.irlQr = function (text, forceMask) {
    const best = window.irlQrMatrix(text, forceMask);
    const n = best.length, q = 4;
    let path = '';
    best.forEach((row, y) => row.forEach((d, x) => { if (d) path += `M${x + q} ${y + q}h1v1h-1z`; }));
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${n + 2 * q} ${n + 2 * q}" shape-rendering="crispEdges" role="img" aria-label="QR code">`
      + `<rect width="100%" height="100%" fill="#fff"/><path d="${path}" fill="#000"/></svg>`;
  };
})();
