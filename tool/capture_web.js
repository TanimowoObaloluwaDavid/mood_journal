// Capture README screenshots and a demo video from the Flutter web build,
// driving headless Chrome over the DevTools Protocol.
//
// Each screen is a separate go_router path, so no tapping is required — the
// app is simply loaded at /#/calendar, /#/insights and so on. That is far more
// reliable than synthesising taps at coordinates.
//
// Usage:
//   node tool/capture_web.js [--port 8099] [--out docs/screens] [--no-video]

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';

const args = process.argv.slice(2);
const opt = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : args[i + 1];
};
const has = (name) => args.includes(`--${name}`);

const PORT = Number(opt('port', 8099));
const OUT = path.resolve(opt('out', 'docs/screens'));
const BASE = `http://127.0.0.1:${PORT}`;
const DEBUG_PORT = 9333;
const PROFILE = path.join(os.tmpdir(), 'mood_journal_capture_profile');
const FRAME_DIR = path.join(os.tmpdir(), 'mood_journal_frames');

// A phone-shaped viewport at 2x, so downscaled screenshots stay crisp.
const VIEWPORT = { width: 390, height: 844, deviceScaleFactor: 2, mobile: true };

const ROUTES = [
  { hash: '', name: '01_home', settle: 30000 },
  { hash: '/calendar', name: '02_calendar', settle: 16000 },
  { hash: '/insights', name: '03_insights', settle: 18000 },
  { hash: '/search', name: '04_search', settle: 16000 },
  { hash: '/settings', name: '05_settings', settle: 16000 },
  { hash: '/entry/demo-2', name: '06_editor', settle: 16000 },
];

const crypto = require('crypto');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Groups of captures that came out byte-identical, i.e. a route failed. */
const identicalScreens = [];

function trackIdentical(file, buffer) {
  const hash = crypto.createHash('md5').update(buffer).digest('hex');
  const existing = identicalScreens.find((g) => g.hash === hash);
  if (existing) {
    existing.names.push(path.basename(file));
  } else {
    identicalScreens.push({ hash, names: [path.basename(file)] });
  }
}

async function waitForCdp() {
  for (let i = 0; i < 60; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${DEBUG_PORT}/json/version`);
      if (res.ok) return await res.json();
    } catch {
      /* not up yet */
    }
    await sleep(500);
  }
  throw new Error('Chrome DevTools endpoint never came up');
}

class Cdp {
  constructor(ws) {
    this.ws = ws;
    this.id = 0;
    this.pending = new Map();
    this.listeners = new Map();
    ws.addEventListener('message', (event) => {
      const msg = JSON.parse(event.data);
      if (msg.id && this.pending.has(msg.id)) {
        const { resolve, reject } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        msg.error ? reject(new Error(JSON.stringify(msg.error))) : resolve(msg.result);
      } else if (msg.method) {
        (this.listeners.get(msg.method) || []).forEach((fn) => fn(msg.params));
      }
    });
  }

  static async connect(url) {
    const ws = new WebSocket(url);
    await new Promise((resolve, reject) => {
      ws.addEventListener('open', resolve, { once: true });
      ws.addEventListener('error', reject, { once: true });
    });
    return new Cdp(ws);
  }

  send(method, params = {}) {
    const id = ++this.id;
    this.ws.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => this.pending.set(id, { resolve, reject }));
  }

  on(method, fn) {
    if (!this.listeners.has(method)) this.listeners.set(method, []);
    this.listeners.get(method).push(fn);
  }

  close() {
    this.ws.close();
  }
}

async function main() {
  fs.mkdirSync(OUT, { recursive: true });

  // A fresh profile every run. Reusing one leaves OPFS handles and a half
  // initialised database behind, and the next launch can come up blank.
  if (!has('keep-profile')) {
    fs.rmSync(PROFILE, { recursive: true, force: true });
  }
  fs.mkdirSync(PROFILE, { recursive: true });

  if (has('video')) {
    fs.rmSync(FRAME_DIR, { recursive: true, force: true });
    fs.mkdirSync(FRAME_DIR, { recursive: true });
  }

  console.log('launching headless Chrome...');
  const chrome = spawn(
    CHROME,
    [
      '--headless=new',
      `--remote-debugging-port=${DEBUG_PORT}`,
      `--user-data-dir=${PROFILE}`,
      '--window-size=390,844',
      '--hide-scrollbars',
      // Software rendering: there is no GPU in this environment, and without
      // these Chrome refuses to composite WebGL, so Flutter renders nothing.
      '--enable-unsafe-swiftshader',
      '--use-gl=angle',
      '--use-angle=swiftshader',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-gpu-sandbox',
      '--autoplay-policy=no-user-gesture-required',
      'about:blank',
    ],
    { stdio: 'ignore' },
  );

  try {
    await waitForCdp();

    const targets = await (await fetch(`http://127.0.0.1:${DEBUG_PORT}/json/list`)).json();
    const page = targets.find((t) => t.type === 'page');
    if (!page) throw new Error('no page target available');

    const cdp = await Cdp.connect(page.webSocketDebuggerUrl);

    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');
    await cdp.send('Emulation.setDeviceMetricsOverride', VIEWPORT);

    console.log('capturing screenshots...');
    for (const route of ROUTES) {
      // A full reload per route, not a hash change.
      //
      // Navigating between two `#/...` URLs on the same document is a
      // same-document navigation, which go_router does not always pick up —
      // routes above the shell were silently not re-rendered, producing
      // screenshots of the previous screen. Bouncing through about:blank
      // forces a genuine cold load, which is also what someone pasting a deep
      // link into the address bar actually gets.
      let buffer = null;
      let attempt = 0;

      while (buffer === null || attempt < 2) {
        attempt++;
        await cdp.send('Page.navigate', { url: 'about:blank' });
        await sleep(400);
        await cdp.send('Page.navigate', { url: `${BASE}/#${route.hash}` });

        // The first load seeds ~78 encrypted entries, which takes longer than
        // you would guess. A blank capture means it had not finished, so
        // retry with a longer wait rather than shipping an empty screenshot.
        await sleep(route.settle * attempt);

        const shot = await cdp.send('Page.captureScreenshot', {
          format: 'png',
          captureBeyondViewport: false,
        });
        buffer = Buffer.from(shot.data, 'base64');

        const looksBlank = buffer.length < 25 * 1024;
        if (looksBlank && attempt < 2) {
          console.log(`  ${route.name}: blank, retrying with a longer wait...`);
          buffer = null;
        }
      }

      const file = path.join(OUT, `${route.name}.png`);
      fs.writeFileSync(file, buffer);
      trackIdentical(file, buffer);
      const kb = (buffer.length / 1024).toFixed(1);
      console.log(`  ${route.name}.png  ${kb} KB`);
    }

    if (identicalScreens.some((g) => g.names.length > 1)) {
      console.warn('WARNING: byte-identical captures mean a route did not render:');
      identicalScreens
        .filter((g) => g.names.length > 1)
        .forEach((g) => console.warn(`  ${g.names.join(' == ')}`));
    }

    if (!has('video')) {
      cdp.close();
      console.log('done (no video requested)');
      return;
    }

    console.log('recording demo video...');
    const frames = [];
    cdp.on('Page.screencastFrame', async ({ data, sessionId }) => {
      const index = String(frames.length).padStart(4, '0');
      fs.writeFileSync(path.join(FRAME_DIR, `f${index}.jpg`), Buffer.from(data, 'base64'));
      frames.push(index);
      await cdp.send('Page.screencastFrameAck', { sessionId }).catch(() => {});
    });

    await cdp.send('Page.startScreencast', {
      format: 'jpeg',
      quality: 85,
      maxWidth: 780,
      maxHeight: 1688,
      everyNthFrame: 1,
    });

    for (const route of ROUTES) {
      // Full reloads here too, for the same reason as the stills: a hash-only
      // change does not reliably re-render routes that sit above the shell.
      await cdp.send('Page.navigate', { url: 'about:blank' });
      await sleep(600);
      await cdp.send('Page.navigate', { url: `${BASE}/#${route.hash}` });
      await sleep(route.name === '01_home' ? 9000 : 6000);
    }

    await sleep(2500);
    await cdp.send('Page.stopScreencast');
    cdp.close();

    console.log(`  ${frames.length} frames in ${FRAME_DIR}`);
    fs.writeFileSync(path.join(FRAME_DIR, 'count.txt'), String(frames.length));
  } finally {
    chrome.kill();
  }
}

main().catch((error) => {
  console.error('capture failed:', error.message);
  process.exit(1);
});
