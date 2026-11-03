// Draws a QR code as a .bmp picture (for Setup.exe's last page, which can't show web pages):
//   node tools/qr-bmp.mjs <text> <out.bmp> [pixels per module]
// Uses the dashboard's own QR generator (dashboard/public/qr.js).
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const [text, out, scaleArg] = process.argv.slice(2);
if (!text || !out) { console.error('usage: node qr-bmp.mjs <text> <out.bmp> [scale]'); process.exit(2); }
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ctx = { window: {}, TextEncoder };
vm.runInNewContext(fs.readFileSync(path.join(root, 'dashboard', 'public', 'qr.js'), 'utf8'), ctx);
const m = ctx.window.irlQrMatrix(text);
const scale = Math.max(1, +scaleArg || 6), quiet = 4, n = m.length, size = (n + 2 * quiet) * scale;

// 24-bit uncompressed BMP, rows bottom-up, each padded to 4 bytes.
const rowBytes = Math.ceil((size * 3) / 4) * 4, pixels = Buffer.alloc(rowBytes * size, 0xff);
for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
  if (!m[y][x]) continue;
  for (let dy = 0; dy < scale; dy++) {
    const row = size - 1 - ((y + quiet) * scale + dy);
    pixels.fill(0, row * rowBytes + (x + quiet) * scale * 3, row * rowBytes + (x + quiet + 1) * scale * 3);
  }
}
const head = Buffer.alloc(54);
head.write('BM', 0); head.writeUInt32LE(54 + pixels.length, 2); head.writeUInt32LE(54, 10);
head.writeUInt32LE(40, 14); head.writeInt32LE(size, 18); head.writeInt32LE(size, 22); head.writeUInt16LE(1, 26); head.writeUInt16LE(24, 28);
head.writeUInt32LE(pixels.length, 34); head.writeInt32LE(2835, 38); head.writeInt32LE(2835, 42);
fs.writeFileSync(out, Buffer.concat([head, pixels]));
console.log(`${size}x${size}`);
