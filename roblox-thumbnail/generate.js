// Renders the Roll a Pet thumbnails/icons (Roblox-style blocky art) to PNG.
// Usage: NODE_PATH=$(npm root -g) node generate.js
const { chromium } = require('playwright');
const path = require('path');
const OUT = path.join(__dirname, 'v2');
const INK = '#2a1150';

// ---------- helpers ----------
function shade(hex, amt) {
  const n = parseInt(hex.slice(1), 16);
  const f = c => Math.max(0, Math.min(255, Math.round(amt < 0 ? c * (1 + amt) : c + (255 - c) * amt)));
  const r = f(n >> 16), g = f((n >> 8) & 255), b = f(n & 255);
  return '#' + ((1 << 24) | (r << 16) | (g << 8) | b).toString(16).slice(1);
}
// Oblique box: front face at (x,y,w,h), depth goes up-right.
function box(x, y, w, h, color, d = 22, sw = 6) {
  const dx = d, dy = -d * 0.7;
  return `<g stroke="${INK}" stroke-width="${sw}" stroke-linejoin="round">
    <polygon points="${x},${y} ${x + dx},${y + dy} ${x + w + dx},${y + dy} ${x + w},${y}" fill="${shade(color, .28)}"/>
    <polygon points="${x + w},${y} ${x + w + dx},${y + dy} ${x + w + dx},${y + h + dy} ${x + w},${y + h}" fill="${shade(color, -.22)}"/>
    <rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${color}"/>
  </g>`;
}
const g = (t, inner) => `<g transform="${t}">${inner}</g>`;

// ---------- Roblox-style avatar ----------
// origin = top-centre of torso. Torso 120x120, head 84x80, limbs 58x120.
const FACES = {
  smile: `<ellipse cx="-17" cy="-48" rx="7" ry="10" fill="${INK}"/><ellipse cx="17" cy="-48" rx="7" ry="10" fill="${INK}"/>
          <path d="M-22,-30 Q0,-12 22,-30" fill="none" stroke="${INK}" stroke-width="6" stroke-linecap="round"/>`,
  grin: `<ellipse cx="-17" cy="-50" rx="7" ry="10" fill="${INK}"/><ellipse cx="17" cy="-50" rx="7" ry="10" fill="${INK}"/>
         <circle cx="-19" cy="-54" r="2.5" fill="#fff"/><circle cx="15" cy="-54" r="2.5" fill="#fff"/>
         <path d="M-24,-32 h48 q0,22 -24,22 q-24,0 -24,-22z" fill="${INK}"/><path d="M-14,-18 q14,10 28,0 q-6,-6 -14,-6 q-8,0 -14,6z" fill="#ff5f7e"/>`,
  shock: `<ellipse cx="-18" cy="-52" rx="10" ry="13" fill="#fff" stroke="${INK}" stroke-width="5"/><ellipse cx="18" cy="-52" rx="10" ry="13" fill="#fff" stroke="${INK}" stroke-width="5"/>
          <circle cx="-17" cy="-50" r="5" fill="${INK}"/><circle cx="17" cy="-50" r="5" fill="${INK}"/>
          <ellipse cx="0" cy="-24" rx="11" ry="14" fill="${INK}"/>
          <path d="M-32,-72 l14,-6 M32,-72 l-14,-6" stroke="${INK}" stroke-width="5" stroke-linecap="round"/>`,
};
function hair(style, color) {
  if (style === 'cap') return `${box(-46, -100, 92, 30, color, 22)}${box(-46, -72, 116, 8, shade(color, -.15), 16)}<circle cx="0" cy="-86" r="7" fill="#fff"/>`;
  if (style === 'spiky') return `<g stroke="${INK}" stroke-width="6" stroke-linejoin="round" fill="${color}">
      <polygon points="-48,-60 -50,-100 -34,-88 -26,-118 -8,-92 6,-122 18,-94 34,-114 40,-88 62,-104 66,-70 48,-64 46,-78 -44,-78 -44,-60"/></g>`;
  // 'bob'
  return `${box(-48, -96, 96, 26, color, 22)}${box(-48, -72, 18, 40, color, 0)}${box(30, -72, 18, 22, color, 0)}`;
}
function arm(sx, angle, skin, sleeve, flip) {
  // arm hangs down from shoulder point (sx, 0); rotate by angle (deg, positive = outward)
  const x = flip ? sx - 58 : sx;
  const piv = flip ? sx : sx;
  return g(`rotate(${flip ? angle : -angle} ${piv} 8)`, box(x, 0, 58, 120, skin) + `<rect x="${x}" y="0" width="58" height="46" fill="${sleeve}" stroke="${INK}" stroke-width="6" stroke-linejoin="round"/>`);
}
function avatar({ skin = '#ffd36e', shirt = '#36b6ff', pants = '#2f3a8f', hairStyle = 'bob', hairColor = '#5a2e12', face = 'smile', arms = [20, 20], logo = true } = {}) {
  const logoSvg = logo ? `<g fill="#fff" transform="translate(-20,30) scale(.4)"><ellipse cx="50" cy="63" rx="17" ry="14"/><circle cx="28" cy="42" r="8"/><circle cx="42" cy="30" r="8.5"/><circle cx="58" cy="30" r="8.5"/><circle cx="72" cy="42" r="8"/></g>` : '';
  return [
    box(-60, 120, 59, 120, pants), box(1, 120, 59, 120, pants),
    arm(-60, arms[0], skin, shirt, true),
    box(-60, 0, 120, 120, shirt), logoSvg,
    arm(60, arms[1], skin, shirt, false),
    box(-42, -82, 84, 80, skin), FACES[face], hair(hairStyle, hairColor),
  ].join('');
}

// ---------- blocky cube pets ----------
// origin = centre of front face. Body 130x110.
const petEyes = `<ellipse cx="-28" cy="-6" rx="11" ry="14" fill="${INK}"/><ellipse cx="28" cy="-6" rx="11" ry="14" fill="${INK}"/>
  <circle cx="-32" cy="-12" r="5" fill="#fff"/><circle cx="24" cy="-12" r="5" fill="#fff"/><circle cx="-24" cy="-1" r="2.5" fill="#fff"/><circle cx="32" cy="-1" r="2.5" fill="#fff"/>
  <ellipse cx="-46" cy="16" rx="10" ry="6" fill="#ff5fa2" opacity=".6"/><ellipse cx="46" cy="16" rx="10" ry="6" fill="#ff5fa2" opacity=".6"/>`;
const S = `stroke="${INK}" stroke-width="6" stroke-linejoin="round" stroke-linecap="round"`;
const PETS = {
  cat: c => `${box(-58, -82, 30, 30, c, 14)}${box(28, -82, 30, 30, c, 14)}${box(-65, -55, 130, 110, c, 30)}
     <path d="M-10,-50 v14 M0,-50 v14 M10,-50 v14" stroke="${shade(c, -.3)}" stroke-width="6" stroke-linecap="round"/>
     ${petEyes}<path d="M-6,8 h12 l-6,7z" fill="#ff5fa2" ${S} stroke-width="3"/><path d="M-12,20 q6,8 12,0 q6,8 12,0" fill="none" ${S} stroke-width="5"/>`,
  dog: c => `${box(-65, -55, 130, 110, c, 30)}${box(-82, -50, 24, 60, shade(c, -.35), 10)}${box(58, -50, 24, 60, shade(c, -.35), 10)}
     ${petEyes}<rect x="-24" y="8" width="48" height="30" rx="8" fill="#fff4e6" ${S} stroke-width="5"/>
     <rect x="-9" y="10" width="18" height="11" rx="4" fill="${INK}"/><path d="M-6,30 q6,14 12,0z" fill="#ff5f7e" ${S} stroke-width="3"/>`,
  dragon: c => `<path d="M-60,-30 L-130,-110 L-110,-40 L-150,-60 L-90,0Z" fill="${shade(c, .2)}" ${S}/>
     <path d="M90,-50 L160,-130 L140,-60 L180,-80 L110,-20Z" fill="${shade(c, .2)}" ${S}/>
     ${box(-50, -88, 18, 34, '#ffd23f', 10)}${box(32, -88, 18, 34, '#ffd23f', 10)}${box(-65, -55, 130, 110, c, 30)}
     <polygon points="-30,-55 -20,-72 -10,-55" fill="#ffd23f" ${S}/><polygon points="-8,-55 4,-78 16,-55" fill="#ffd23f" ${S}/><polygon points="18,-55 28,-70 38,-55" fill="#ffd23f" ${S}/>
     ${petEyes}<rect x="-30" y="12" width="60" height="28" rx="10" fill="${shade(c, .45)}" ${S} stroke-width="5"/>
     <path d="M-16,18 l6,8 M16,18 l-6,8" stroke="${INK}" stroke-width="5" stroke-linecap="round"/>
     <path d="M-14,40 l5,9 l5,-9 M4,40 l5,9 l5,-9" fill="#fff" ${S} stroke-width="3"/>`,
  bunny: c => `${box(-44, -140, 26, 88, c, 12)}${box(18, -140, 26, 88, c, 12)}
     <rect x="-38" y="-130" width="14" height="66" fill="#ffb3cf"/><rect x="24" y="-130" width="14" height="66" fill="#ffb3cf"/>
     ${box(-65, -55, 130, 110, c, 30)}${petEyes}<path d="M-6,10 h12 l-6,6z" fill="#ff5fa2" ${S} stroke-width="3"/>
     <rect x="-8" y="20" width="16" height="12" fill="#fff" ${S} stroke-width="3"/>`,
  unicorn: c => `${box(-65, -55, 130, 110, c, 30)}
     <polygon points="-10,-60 0,-140 14,-60" fill="#ffd23f" ${S}/>
     ${box(-80, -70, 40, 30, '#ff7ad9', 14)}${box(-90, -40, 26, 60, '#b46bff', 8)}${box(40, -72, 40, 22, '#36b6ff', 14)}
     ${petEyes}<path d="M-12,22 q12,12 24,0" fill="none" ${S} stroke-width="5"/>`,
};
function pet(kind, color, feet = true) {
  const f = feet ? `${box(-52, 52, 34, 20, shade(color, -.1), 14)}${box(18, 52, 34, 20, shade(color, -.1), 14)}` : '';
  return f + PETS[kind](color);
}
const PET_COLORS = { cat: '#ffa94d', dog: '#f2c08a', dragon: '#3ee07a', bunny: '#f4f0ff', unicorn: '#ffffff' };

// ---------- dice ----------
const PAW = `<ellipse cx="50" cy="63" rx="17" ry="14"/><circle cx="28" cy="42" r="8"/><circle cx="42" cy="30" r="8.5"/><circle cx="58" cy="30" r="8.5"/><circle cx="72" cy="42" r="8"/>`;
const pawAt = (x, y, s) => `<g transform="translate(${x},${y}) scale(${s}) translate(-50,-50)">${PAW}</g>`;
const DICE = `<g ${S} stroke-width="12">
    <polygon points="0,-170 150,-85 0,0 -150,-85" fill="#fff"/>
    <polygon points="-150,-85 0,0 0,170 -150,85" fill="#ddd0ff"/>
    <polygon points="0,0 150,-85 150,85 0,170" fill="#b9a0f0"/></g>
  <polyline points="-118,-82 0,-150 40,-128" fill="none" stroke="#fff" stroke-width="8" stroke-linecap="round"/>
  <g transform="matrix(1.5,0.85,-1.5,0.85,0,-170)" fill="#ff4fa3">${pawAt(50, 50, .62)}</g>
  <g transform="matrix(1.5,0.85,0,1.7,-150,-85)" fill="#8b3dff">${pawAt(28, 28, .38)}${pawAt(72, 72, .38)}</g>
  <g transform="matrix(1.5,-0.85,0,1.7,0,0)" fill="#5b1fd1">${pawAt(25, 25, .32)}${pawAt(50, 50, .32)}${pawAt(75, 75, .32)}</g>`;

// ---------- shared decor ----------
const DEFS = `<defs>
  <radialGradient id="glow"><stop offset="0" stop-color="#fff6a8" stop-opacity=".95"/><stop offset=".45" stop-color="#ffd23f" stop-opacity=".45"/><stop offset="1" stop-color="#ffd23f" stop-opacity="0"/></radialGradient>
  <radialGradient id="glowPink"><stop offset="0" stop-color="#ffffff" stop-opacity=".95"/><stop offset=".4" stop-color="#ff7ad9" stop-opacity=".55"/><stop offset="1" stop-color="#ff7ad9" stop-opacity="0"/></radialGradient>
  <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff7b0"/><stop offset=".45" stop-color="#ffd23f"/><stop offset="1" stop-color="#ff8a1f"/></linearGradient>
  <linearGradient id="ice" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff"/><stop offset=".55" stop-color="#bff3ff"/><stop offset="1" stop-color="#5fd0ff"/></linearGradient>
  <linearGradient id="mythic" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#ff4fa3"/><stop offset=".25" stop-color="#ffb627"/><stop offset=".5" stop-color="#3ee07a"/><stop offset=".75" stop-color="#36b6ff"/><stop offset="1" stop-color="#b46bff"/></linearGradient>
  <linearGradient id="legend" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffe066"/><stop offset="1" stop-color="#ff9f1c"/></linearGradient>
  <linearGradient id="epic" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#d59bff"/><stop offset="1" stop-color="#8b3dff"/></linearGradient>
  <linearGradient id="rare" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#6fd6ff"/><stop offset="1" stop-color="#2f7bff"/></linearGradient>
  <linearGradient id="common" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#d9e2ec"/><stop offset="1" stop-color="#8a9bb0"/></linearGradient>
  <linearGradient id="pill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5dff9b"/><stop offset="1" stop-color="#14b85a"/></linearGradient>
</defs>`;
function background(W, H, cx, cy, c1 = '#ff7ad9', c2 = '#8b3dff', c3 = '#1e0a5c', seed = 7) {
  let rays = '';
  const n = 18, R = Math.max(W, H) * 1.6;
  for (let i = 0; i < n; i++) {
    const a0 = (i / n) * Math.PI * 2, a1 = a0 + Math.PI / n;
    rays += `<path d="M0,0 L${R * Math.cos(a0)},${R * Math.sin(a0)} L${R * Math.cos(a1)},${R * Math.sin(a1)}Z"/>`;
  }
  let s = seed; const rnd = () => ((s = (s * 9301 + 49297) % 233280) / 233280);
  const cols = ['#ffd23f', '#3ee07a', '#36b6ff', '#ff4fa3', '#ffffff'];
  let conf = '';
  const k = W / 1920;
  for (let i = 0; i < 60; i++) {
    const x = rnd() * W, y = rnd() * H, w = 26 * k * (.6 + rnd() * .8);
    conf += `<rect x="${x}" y="${y}" width="${w}" height="${w * .45}" rx="${w * .15}" fill="${cols[i % 5]}" opacity=".8" transform="rotate(${rnd() * 360} ${x} ${y})"/>`;
  }
  return `<radialGradient id="bg${seed}" cx="${cx / W * 100}%" cy="${cy / H * 100}%" r="80%"><stop offset="0" stop-color="${c1}"/><stop offset=".38" stop-color="${c2}"/><stop offset="1" stop-color="${c3}"/></radialGradient>
    <rect width="${W}" height="${H}" fill="url(#bg${seed})"/>
    <g transform="translate(${cx},${cy})" fill="#fff" opacity=".2">${rays}</g>${conf}`;
}
const spark = (x, y, r, o = .9) => `<path transform="translate(${x},${y}) scale(${r / 50})" d="M0,-50 C6,-12 12,-6 50,0 C12,6 6,12 0,50 C-6,12 -12,6 -50,0 C-12,-6 -6,-12 0,-50Z" fill="#fff" opacity="${o}"/>`;
function text(str, x, y, size, fill, { anchor = 'start', sw, depth } = {}) {
  sw = sw ?? size * .11; depth = depth ?? size * .07;
  return `<g class="t" paint-order="stroke" stroke-linejoin="round" text-anchor="${anchor}">
    <text x="${x}" y="${y + depth}" font-size="${size}" fill="${INK}" stroke="${INK}" stroke-width="${sw * 1.3}">${str}</text>
    <text x="${x}" y="${y}" font-size="${size}" fill="${fill}" stroke="${INK}" stroke-width="${sw}">${str}</text></g>`;
}
function tag(label, grad, x, y, rot = 0, size = 42) {
  const w = label.length * size * .62 + 70, h = size * 1.6;
  return g(`translate(${x},${y}) rotate(${rot})`, `<rect x="${-w / 2}" y="${-h / 2}" width="${w}" height="${h}" rx="${h / 2}" fill="url(#${grad})" stroke="${INK}" stroke-width="8"/>
    <text class="t" y="${size * .38}" text-anchor="middle" font-size="${size}" fill="#fff" paint-order="stroke" stroke="${INK}" stroke-width="${size * .26}" stroke-linejoin="round">${label}</text>`);
}
function pillCTA(label, x, y, w, rot = -4, size = 62) {
  return g(`translate(${x},${y}) rotate(${rot})`, `<rect width="${w}" height="120" rx="60" fill="${INK}" transform="translate(0,12)"/>
    <rect width="${w}" height="120" rx="60" fill="url(#pill)" stroke="${INK}" stroke-width="10"/>
    <rect x="34" y="16" width="${w - 68}" height="30" rx="15" fill="#fff" opacity=".35"/>
    <text class="t" x="${w / 2}" y="82" text-anchor="middle" font-size="${size}" fill="#fff" paint-order="stroke" stroke="#0d5a2c" stroke-width="12" stroke-linejoin="round">${label}</text>`);
}
const glowAt = (x, y, r, id = 'glow') => `<circle cx="${x}" cy="${y}" r="${r}" fill="url(#${id})"/>`;

// ---------- scenes ----------
const scenes = {
  // 1. Player throwing the dice, pets bursting out
  'thumbnail-1-roll': [1920, 1080, () => `${background(1920, 1080, 1450, 560)}${glowAt(1450, 560, 520)}
    ${spark(1040, 150, 34)}${spark(1830, 140, 26)}${spark(1180, 930, 30)}${spark(80, 980, 24, .6)}
    ${g('translate(1480,640) rotate(-10) scale(1.05)', DICE)}
    ${g('translate(1470,250) rotate(-6) scale(1.35)', pet('dragon', PET_COLORS.dragon))}
    ${g('translate(1120,520) rotate(-12) scale(1.05)', pet('cat', PET_COLORS.cat))}
    ${g('translate(1790,760) rotate(10) scale(1.1)', pet('dog', PET_COLORS.dog))}
    ${tag('MYTHIC', 'mythic', 1760, 360, 8)}${tag('RARE', 'rare', 1100, 680, -10, 38)}${tag('LEGENDARY', 'legend', 1700, 990, 6, 40)}
    ${g('translate(820,560) rotate(4) scale(1.55)', avatar({ face: 'grin', arms: [25, 150], hairStyle: 'cap', hairColor: '#ff4f5e', shirt: '#36b6ff' }))}
    ${g('rotate(-5 400 300)', text('ROLL', 70, 330, 290, 'url(#gold)') + text('A PET!', 90, 560, 210, 'url(#ice)'))}
    ${pillCTA('1 IN 1,000,000 PETS!', 70, 880, 700, -3, 58)}`],

  // 2. Mythic reveal: shocked player, giant rainbow dragon
  'thumbnail-2-mythic': [1920, 1080, () => `${background(1920, 1080, 1180, 470, '#ffd1f2', '#c04dff', '#2a0a5c', 11)}
    ${glowAt(1180, 470, 600, 'glowPink')}${spark(820, 160, 40)}${spark(1640, 130, 34)}${spark(1760, 640, 30)}${spark(900, 760, 26)}
    ${g('translate(1180,500) rotate(-4) scale(2.7)', pet('dragon', '#b46bff'))}
    ${g('translate(400,620) rotate(6) scale(1.85)', avatar({ face: 'shock', arms: [150, 150], hairStyle: 'spiky', hairColor: '#ffd23f', shirt: '#ff4fa3', pants: '#3b2a7a' }))}
    ${g('rotate(-4 960 900)', text('MYTHIC!', 1180, 990, 230, 'url(#mythic)', { anchor: 'middle' }))}
    ${tag('1 IN 1,000,000', 'legend', 1650, 690, 8, 44)}
    ${g('rotate(-5 300 100)', text('ROLL A PET', 60, 170, 140, 'url(#gold)'))}`],

  // 3. Pet squad / collect them all
  'thumbnail-3-collect': [1920, 1080, () => `${background(1920, 1080, 960, 560, '#7ae2ff', '#3d6bff', '#160a5c', 23)}
    ${glowAt(960, 560, 560)}${spark(150, 300, 30)}${spark(1780, 300, 34)}${spark(520, 980, 22, .7)}${spark(1420, 980, 22, .7)}
    ${g('translate(960,520) scale(1.45)', avatar({ face: 'grin', arms: [150, 150], hairStyle: 'bob', hairColor: '#2b1a10', shirt: '#3ee07a', pants: '#24306e' }))}
    ${g('translate(250,700) rotate(-8) scale(1.05)', pet('bunny', PET_COLORS.bunny))}
    ${g('translate(560,770) rotate(-4) scale(1.05)', pet('cat', PET_COLORS.cat))}
    ${g('translate(1340,770) rotate(4) scale(1.05)', pet('dog', PET_COLORS.dog))}
    ${g('translate(1660,700) rotate(8) scale(1.05)', pet('unicorn', PET_COLORS.unicorn))}
    ${tag('COMMON', 'common', 250, 900, -8, 36)}${tag('RARE', 'rare', 560, 960, -4, 36)}${tag('EPIC', 'epic', 1340, 960, 4, 36)}${tag('LEGENDARY', 'legend', 1660, 900, 8, 36)}
    ${text('ROLL A PET!', 960, 200, 210, 'url(#gold)', { anchor: 'middle' })}
    ${tag('COLLECT THEM ALL!', 'pill', 960, 290, -2, 50)}`],

  // Icons
  'icon-1-player': [512, 512, () => `${background(512, 512, 256, 300, '#ff7ad9', '#8b3dff', '#1e0a5c', 5)}${glowAt(256, 320, 260)}
    ${g('translate(398,398) rotate(-8) scale(.5)', DICE)}
    ${g('translate(160,350) rotate(5) scale(1.1)', avatar({ face: 'grin', arms: [20, 20], hairStyle: 'cap', hairColor: '#ff4f5e' }))}
    ${g('translate(392,215) rotate(10) scale(.68)', pet('cat', PET_COLORS.cat))}
    ${g('rotate(-5 256 70)', text('ROLL A PET', 256, 98, 92, 'url(#gold)', { anchor: 'middle' }))}`],
  'icon-2-mythic': [512, 512, () => `${background(512, 512, 256, 280, '#ffd1f2', '#c04dff', '#2a0a5c', 9)}${glowAt(256, 290, 270, 'glowPink')}
    ${spark(70, 200, 22)}${spark(450, 380, 18)}
    ${g('translate(256,320) rotate(-4) scale(1.35)', pet('dragon', '#b46bff'))}
    ${g('rotate(-5 256 70)', text('ROLL A PET', 256, 98, 92, 'url(#gold)', { anchor: 'middle' }))}
    ${tag('MYTHIC', 'mythic', 256, 470, -3, 40)}`],
};

(async () => {
  const only = process.argv[2];
  const b = await chromium.launch();
  for (const [name, [W, H, fn]] of Object.entries(scenes)) {
    if (only && !name.includes(only)) continue;
    const p = await b.newPage({ viewport: { width: W, height: H } });
    await p.setContent(`<!doctype html><html><head><meta charset="utf-8">
      <link href="https://fonts.googleapis.com/css2?family=Luckiest+Guy&display=block" rel="stylesheet">
      <style>html,body{margin:0;overflow:hidden}.t{font-family:'Luckiest Guy',sans-serif}svg{display:block}</style></head>
      <body><svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">${DEFS}${fn()}</svg></body></html>`, { waitUntil: 'networkidle' });
    await p.evaluate(() => document.fonts.ready);
    await p.screenshot({ path: path.join(OUT, `roll-a-pet-${name}-${W}x${H}.png`) });
    await p.close();
  }
  await b.close();
})();
