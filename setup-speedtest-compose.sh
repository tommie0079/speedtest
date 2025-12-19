
#!/usr/bin/env bash
set -euo pipefail

# One-file installer: Docker Compose speedtest + Caddy TLS
# Usage:
#   1) Save as setup-speedtest-compose.sh
#   2) Edit DOMAIN and TESTFILE_SIZE_MB below or export DOMAIN before running
#   3) chmod +x setup-speedtest-compose.sh
#   4) ./setup-speedtest-compose.sh
#
# Requirements: docker, docker-compose (or Docker Compose v2 as 'docker compose').

APP_DIR="speedtest-server"
IMAGE_NAME="speedtest-server"
TESTFILE_SIZE_MB="${TESTFILE_SIZE_MB:-200}"   # default 200 MB
DOMAIN="${DOMAIN:-}"                         # set like: DOMAIN=your.domain.com ./setup...

echo "Creating folder: ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}"
cd "${APP_DIR}"

# --------------- simple-speedtest.html ---------------
cat > simple-speedtest.html <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>Simple Speedtest</title>
  <style>
    :root{--bg:#0f172a;--card:#0b1220;--muted:#94a3b8;--accent:#38bdf8;--accent2:#22c55e}
    body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial;max-width:1000px;margin:18px auto;padding:18px;color:#e5e7eb;background:linear-gradient(180deg,#020617,#020617 40%,#020617)}
    h1{font-size:clamp(20px,4vw,28px);margin:0 0 8px}
    .card{background:var(--card);border-radius:12px;padding:16px;box-shadow:0 8px 24px rgba(0,0,0,.45)}
    label{display:block;margin-top:10px;font-size:13px;color:var(--muted)}
    input, select{width:100%;padding:10px;margin-top:6px;border-radius:10px;border:1px solid #121826;background:#020617;color:#e5e7eb}
    button{margin-top:16px;padding:12px;border-radius:12px;border:0;background:linear-gradient(135deg,var(--accent),var(--accent2));color:#020617;font-weight:700;width:100%}
    pre{background:#020617;padding:12px;border-radius:12px;overflow:auto;font-size:13px;white-space:pre-wrap}
    .row{display:grid;grid-template-columns:1fr 1fr;gap:16px}
    @media (max-width:820px){.row{grid-template-columns:1fr}}
    .muted{color:var(--muted);font-size:13px;margin-top:6px}
  </style>
</head>
<body>
  <div class="card">
    <h1>Simple Speedtest</h1>
    <p class="muted">Ping, parallel Download and Upload. Host this page together with the server below (same origin) for best results.</p>

    <div class="row">
      <div>
        <label>Ping URL (small):</label>
        <input id="pingUrl" type="text" value="/ping.txt" />

        <label>Download URL (large file):</label>
        <input id="downloadUrl" type="text" value="/testfile.bin" />

        <label>Download runs:</label>
        <input id="downloadRuns" type="number" value="3" min="1" />

        <label>Parallel download connections:</label>
        <input id="parallel" type="number" value="4" min="1" max="16" />

        <label>Upload URL (POST):</label>
        <input id="uploadUrl" type="text" value="/upload" />

        <label>Upload payload size (MB):</label>
        <input id="uploadSize" type="number" value="5" min="1" />

        <button id="startAll">Run Speedtest</button>
      </div>

      <div>
        <h3>Results</h3>
        <pre id="output">Idle. Press "Run Speedtest".</pre>
      </div>
    </div>
  </div>

<script>
const $ = id => document.getElementById(id);
const out = $('output');
function log(...args){ out.textContent += "\\n" + args.join(' '); out.scrollTop = out.scrollHeight }
function clearLog(){ out.textContent = '' }

async function ping(url, attempts = 4){
  const times = [];
  for(let i=0;i<attempts;i++){
    const t0 = performance.now();
    try{
      await fetch(url + (url.includes('?') ? '&' : '?') + 'cb=' + Date.now(), {cache: 'no-store', mode:'cors'});
      const t1 = performance.now();
      times.push(t1-t0);
    }catch(e){
      times.push(Infinity);
    }
    await new Promise(r=>setTimeout(r, 150));
  }
  const valid = times.filter(t=>isFinite(t));
  const avg = valid.length ? valid.reduce((a,b)=>a+b,0)/valid.length : Infinity;
  return {times,avg};
}

async function downloadTest(url, runs=3, parallel=4){
  const results = [];
  for(let i=0;i<runs;i++){
    const t0 = performance.now();
    try{
      const fetches = [];
      for(let p=0;p<parallel;p++){
        fetches.push(fetch(url + (url.includes('?') ? '&' : '?') + 'cb=' + Date.now() + '_' + i + '_' + p, {cache:'no-store', mode:'cors'}).then(r=>r.arrayBuffer()));
      }
      const buffers = await Promise.all(fetches);
      const bytes = buffers.reduce((s,b)=>s+b.byteLength,0);
      const t1 = performance.now();
      results.push({bytes, ms: t1-t0});
      log(`Download run ${i+1}: ${bytes} bytes via ${parallel} conns in ${(t1-t0).toFixed(1)} ms`);
    }catch(e){
      log('Download run error:', e.message || e);
      results.push({bytes:0,ms:Infinity});
    }
    await new Promise(r=>setTimeout(r, 300));
  }
  const valid = results.filter(r=>isFinite(r.ms) && r.bytes>0);
  if(!valid.length) return {averageMbps:0,results};
  const mbps = valid.map(r => (r.bytes*8)/(r.ms/1000)/(1000*1000));
  const avg = mbps.reduce((a,b)=>a+b,0)/mbps.length;
  return {averageMbps:avg,results,mbps};
}

async function uploadTest(url, sizeMB=5){
  const size = Math.max(1, Math.floor(sizeMB)) * 1024 * 1024;
  const arr = new Uint8Array(size);
  for(let i=0;i<size;i+=65536){
    crypto.getRandomValues(arr.subarray(i, Math.min(i+65536,size)));
  }
  const blob = new Blob([arr]);
  const t0 = performance.now();
  try{
    const resp = await fetch(url, {method:'POST', body: blob, mode:'cors'});
    const t1 = performance.now();
    const ms = t1 - t0;
    const bytes = size;
    const mbps = (bytes*8)/(ms/1000)/(1000*1000);
    return {bytes,ms,mbps,status: resp.status};
  }catch(e){
    return {error: e.message || e};
  }
}

$('startAll').addEventListener('click', async ()=>{
  clearLog();
  const pingUrl = $('pingUrl').value.trim();
  const downloadUrl = $('downloadUrl').value.trim();
  const downloadRuns = parseInt($('downloadRuns').value,10) || 3;
  const parallel = parseInt($('parallel').value,10) || 4;
  const uploadUrl = $('uploadUrl').value.trim();
  const uploadSize = parseInt($('uploadSize').value,10) || 5;

  log('Starting tests...');
  log('\\n-- PING --');
  const p = await ping(pingUrl, 4);
  if(isFinite(p.avg)) log(`Ping avg: ${p.avg.toFixed(1)} ms`); else log('Ping failed (check URL/CORS)');

  log('\\n-- DOWNLOAD --');
  const d = await downloadTest(downloadUrl, downloadRuns, parallel);
  if(d.averageMbps){
    log(`Download average: ${d.averageMbps.toFixed(2)} Mbps`);
  } else {
    log('Download test failed or returned 0 bytes. Ensure testfile exists and CORS allows fetch.');
  }

  log('\\n-- UPLOAD --');
  const u = await uploadTest(uploadUrl, uploadSize);
  if(u.error) log('Upload error:', u.error);
  else log(`Upload: ${u.bytes} bytes in ${u.ms.toFixed(1)} ms => ${u.mbps.toFixed(2)} Mbps (HTTP ${u.status})`);

  log('\\nDone. Note: Browser-based tests include client and network overhead.');
});
</script>
</body>
</html>
HTML

# --------------- server.js ---------------
cat > server.js <<'NODE'
const express = require('express');
const fs = require('fs');
const path = require('path');
const app = express();
const PORT = process.env.PORT || 8000;

// Simple permissive CORS for testing
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

// serve static files from this directory (including simple-speedtest.html)
app.use(express.static(__dirname));

// tiny ping file
app.get('/ping.txt', (req, res) => {
  res.type('text/plain').send('pong');
});

// serve testfile.bin
app.get('/testfile.bin', (req, res) => {
  const p = path.join(__dirname, 'testfile.bin');
  if (!fs.existsSync(p)) return res.status(404).send('testfile.bin not found');
  res.sendFile(p);
});

// accept uploads - raw binary
app.post('/upload', (req, res) => {
  let received = 0;
  req.on('data', chunk => { received += chunk.length; });
  req.on('end', () => {
    console.log('Received', received, 'bytes');
    res.status(200).send(`OK ${received}`);
  });
  req.on('error', err => {
    console.error('Upload error', err);
    res.sendStatus(500);
  });
});

app.listen(PORT, () => console.log(`Speedtest server listening on port ${PORT}`));
NODE

# --------------- package.json ---------------
cat > package.json <<'JSON'
{
  "name": "speedtest-server",
  "version": "1.0.0",
  "main": "server.js",
  "license": "MIT",
  "dependencies": {
    "express": "^4.18.2"
  }
}
JSON

# --------------- Dockerfile ---------------
cat > Dockerfile <<'DOCKER'
FROM node:18-alpine
WORKDIR /app
COPY package.json ./
RUN npm ci --only=production
COPY server.js ./
COPY simple-speedtest.html ./
COPY testfile.bin . || true
EXPOSE 8000
CMD ["node", "server.js"]
DOCKER

# --------------- docker-compose.yml ---------------
cat > docker-compose.yml <<'YML'
version: "3.8"
services:
  speedtest:
    build: .
    container_name: speedtest
    restart: unless-stopped
    expose:
      - "8000"
    # optional: you can mount a bigger testfile from the host:
    # volumes:
    #   - ./testfile.bin:/app/testfile.bin:ro

  caddy:
    image: caddy:2
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    depends_on:
      - speedtest
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    environment:
      - DOMAIN=${DOMAIN}
volumes:
  caddy_data:
  caddy_config:
YML

# --------------- Caddyfile ---------------
cat > Caddyfile <<'CADDY'
{$DOMAIN} {
  reverse_proxy speedtest:8000
  encode zstd gzip
}

# helpful fallback for HTTP access (if you didn't set DOMAIN yet)
http:// {
  reverse_proxy speedtest:8000
}
CADDY

# --------------- create testfile.bin ---------------
echo "Creating testfile.bin of ${TESTFILE_SIZE_MB} MB (this may take a while)..."
if command -v dd >/dev/null 2>&1; then
  dd if=/dev/urandom of=testfile.bin bs=1M count="${TESTFILE_SIZE_MB}" status=none || true
elif command -v head >/dev/null 2>&1; then
  head -c $((TESTFILE_SIZE_MB * 1024 * 1024)) /dev/urandom > testfile.bin || true
else
  echo "Could not create testfile.bin automatically. Please create a file named testfile.bin (~${TESTFILE_SIZE_MB}MB) in this folder and re-run."
fi

echo
echo "Files created in $(pwd):"
ls -lh

# --------------- Bring up stack ---------------
echo
echo "Starting stack with docker-compose..."
if command -v docker-compose >/dev/null 2>&1; then
  docker-compose up -d --build
else
  # docker compose v2
  docker compose up -d --build
fi

echo
echo "If you set DOMAIN to a real domain that points to this server, Caddy will request TLS certs automatically."
if [ -n "${DOMAIN}" ]; then
  echo "Open: https://${DOMAIN}/simple-speedtest.html"
else
  IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost')"
  echo "No DOMAIN set. Open in browser via:"
  echo "  http://${IP}/simple-speedtest.html"
  echo ""
  echo "To enable HTTPS with a real certificate, re-run the script with DOMAIN set, e.g.:"
  echo "  DOMAIN=your.domain.com ./setup-speedtest-compose.sh"
fi

echo
echo "To stop: (from inside this folder) docker compose down"
echo "To view logs: docker compose logs -f caddy"


