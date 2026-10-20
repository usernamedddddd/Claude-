// Renders the 3D Roblox-style thumbnails: NODE_PATH=$(npm root -g) node render3d.js [scene]
const http = require('http'), fs = require('fs'), path = require('path');
const { chromium } = require('playwright');
const ROOT = __dirname, OUT = path.join(ROOT, 'v3');
const JOBS = [['mythic', 1920, 1080, 'thumbnail-1-mythic'], ['noobpro', 1920, 1080, 'thumbnail-2-noob-vs-pro'], ['roll', 1920, 1080, 'thumbnail-3-roll'], ['icon', 512, 512, 'icon']];
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.woff2': 'font/woff2' };
const server = http.createServer((req, res) => {
  const f = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
  if (!f.startsWith(ROOT) || !fs.existsSync(f)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': TYPES[path.extname(f)] || 'application/octet-stream' }); fs.createReadStream(f).pipe(res);
}).listen(0, async () => {
  const port = server.address().port, only = process.argv[2];
  const b = await chromium.launch({ args: ['--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  for (const [s, w, h, name] of JOBS) {
    if (only && s !== only) continue;
    const p = await b.newPage({ viewport: { width: w, height: h } });
    p.on('pageerror', e => console.error(s, e.message));
    await p.goto(`http://127.0.0.1:${port}/scene3d.html?s=${s}&w=${w}&h=${h}`);
    await p.waitForFunction(() => window.done, null, { timeout: 120000 });
    const png = await p.evaluate(() => window.renderPNG());
    fs.writeFileSync(path.join(OUT, `rng-pet-legends-${name}-${w}x${h}.png`), Buffer.from(png.split(',')[1], 'base64'));
    console.log('rendered', name);
    await p.close();
  }
  await b.close(); server.close();
});
