// Debug helper: load the web app once, print console output and page errors,
// then screenshot. Used to work out why a build is rendering blank.
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const PORT = process.argv[2] || '8099';
const URL = process.argv[3] || `http://127.0.0.1:${PORT}/#/`;
const WAIT = Number(process.argv[4] || 25000);
const PROFILE = path.join(os.tmpdir(), 'mood_journal_debug_profile');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

fs.rmSync(PROFILE, { recursive: true, force: true });

(async () => {
  const chrome = spawn(CHROME, [
    '--headless=new',
    '--remote-debugging-port=9444',
    `--user-data-dir=${PROFILE}`,
    '--window-size=390,844',
    '--enable-unsafe-swiftshader',
    '--use-gl=angle',
    '--use-angle=swiftshader',
    '--no-first-run',
    '--no-default-browser-check',
    'about:blank',
  ], { stdio: 'ignore' });

  try {
    let version;
    for (let i = 0; i < 60; i++) {
      try {
        version = await (await fetch('http://127.0.0.1:9444/json/version')).json();
        break;
      } catch { await sleep(500); }
    }
    if (!version) throw new Error('no CDP');

    const targets = await (await fetch('http://127.0.0.1:9444/json/list')).json();
    const page = targets.find((t) => t.type === 'page');
    const ws = new WebSocket(page.webSocketDebuggerUrl);
    await new Promise((res, rej) => {
      ws.addEventListener('open', res, { once: true });
      ws.addEventListener('error', rej, { once: true });
    });

    let id = 0;
    const pending = new Map();
    ws.addEventListener('message', (e) => {
      const m = JSON.parse(e.data);
      if (m.id && pending.has(m.id)) {
        pending.get(m.id)(m.result);
        pending.delete(m.id);
      } else if (m.method === 'Runtime.consoleAPICalled') {
        const text = (m.params.args || [])
          .map((a) => a.value ?? a.description ?? a.type)
          .join(' ');
        console.log(`[console.${m.params.type}] ${text}`);
      } else if (m.method === 'Runtime.exceptionThrown') {
        const d = m.params.exceptionDetails;
        console.log(`[EXCEPTION] ${d.text} ${d.exception?.description || ''}`);
      } else if (m.method === 'Log.entryAdded') {
        console.log(`[log.${m.params.entry.level}] ${m.params.entry.text}`);
      }
    });

    const send = (method, params = {}) => {
      const mid = ++id;
      ws.send(JSON.stringify({ id: mid, method, params }));
      return new Promise((r) => pending.set(mid, r));
    };

    await send('Runtime.enable');
    await send('Log.enable');
    await send('Page.enable');
    await send('Emulation.setDeviceMetricsOverride', {
      width: 390, height: 844, deviceScaleFactor: 2, mobile: true,
    });

    console.log(`navigating to ${URL}, waiting ${WAIT}ms`);
    await send('Page.navigate', { url: URL });
    await sleep(WAIT);

    const shot = await send('Page.captureScreenshot', { format: 'png' });
    fs.writeFileSync('debug.png', Buffer.from(shot.data, 'base64'));
    console.log(`\nwrote debug.png (${(fs.statSync('debug.png').size / 1024).toFixed(1)} KB)`);
    ws.close();
  } finally {
    chrome.kill();
  }
})().catch((e) => { console.error(e.message); process.exit(1); });
