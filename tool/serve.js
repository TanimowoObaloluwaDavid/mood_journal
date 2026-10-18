// Minimal static file server for the built Flutter web app.
//
// Two things a generic server gets wrong and drift does not:
//
//   1. `.wasm` must be served as application/wasm, or the browser refuses to
//      stream-compile it and drift falls over with a confusing error.
//   2. drift uses OPFS for persistence when the page is cross-origin isolated,
//      which needs COOP/COEP headers. Without them it silently falls back to
//      IndexedDB.
//
// Usage: node tool/serve.js [port] [root]

const http = require('http');
const fs = require('fs');
const path = require('path');

const port = Number(process.argv[2] || 8099);
const root = path.resolve(process.argv[3] || 'build/web');

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.bin': 'application/octet-stream',
  '.symbols': 'text/plain; charset=utf-8',
};

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  let filePath = path.join(root, decodeURIComponent(url.pathname));

  // Directory traversal guard.
  if (!filePath.startsWith(root)) {
    res.writeHead(403).end('forbidden');
    return;
  }

  if (fs.existsSync(filePath) && fs.statSync(filePath).isDirectory()) {
    filePath = path.join(filePath, 'index.html');
  }

  if (!fs.existsSync(filePath)) {
    // Flutter web is an SPA: unknown paths fall back to index.html so deep
    // links like /calendar work on refresh.
    filePath = path.join(root, 'index.html');
  }

  const type = TYPES[path.extname(filePath).toLowerCase()] || 'application/octet-stream';

  res.writeHead(200, {
    'Content-Type': type,
    // Enables OPFS-backed persistence for drift.
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Cross-Origin-Embedder-Policy': 'require-corp',
    'Cross-Origin-Resource-Policy': 'same-origin',
    'Cache-Control': 'no-store',
  });

  fs.createReadStream(filePath).pipe(res);
});

server.listen(port, '127.0.0.1', () => {
  console.log(`serving ${root} on http://127.0.0.1:${port}`);
});
