#!/usr/bin/env bash
# AMUX-4685 — cdp.mjs must tell amux it is driving, OVER A SELF-SIGNED TLS CERT.
#
# THE DEFECT: the activity reaper closes a profile with no amux browser verb for
# AMUX_BROWSER_ACTIVITY_REAP_S (300 by default). Raw CDP traffic goes straight to
# Chrome, so a browser under continuous use read as idle and was closed. Measured
# 2026-09-15: three kills while driving dashboard overlays, one mid-sweep.
#
# WHY THIS CELL EXISTS AT ALL, and it is not the obvious reason. The reaper half is
# covered by Rust tests. What no Rust test can see is whether the DRIVER's request
# ever leaves the box. amux serves HTTPS with a SELF-SIGNED certificate (every call
# in CLAUDE.md is `curl -sk`), and Node's fetch rejects those with
# DEPTH_ZERO_SELF_SIGNED_CERT. The first cut of amuxKeepalive used fetch inside a
# best-effort catch, so on every real amux server it threw, was swallowed, and did
# nothing, while looking exactly like a working feature.
#
# So this serves a genuinely self-signed HTTPS endpoint and asserts the keepalive
# ARRIVED. A plain-HTTP recorder would pass against the broken version.
#
# Exit 0 = all pass, 1 = a failure.
set -euo pipefail

cd "$(dirname "$0")/.."
PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; [ -n "${SRV_PID:-}" ] && kill "$SRV_PID" 2>/dev/null || true' EXIT

if ! command -v openssl >/dev/null 2>&1; then
  echo "SKIP: openssl is not available, so a self-signed endpoint cannot be built"
  echo "  population: 0 cells (unmeasured)"
  exit 0
fi

openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 1 -subj "/CN=localhost" >/dev/null 2>&1

cat > "$TMP/server.mjs" <<'JS'
import https from 'node:https';
import { readFileSync, writeFileSync } from 'node:fs';
const dir = process.argv[2];
const srv = https.createServer(
  { key: readFileSync(`${dir}/key.pem`), cert: readFileSync(`${dir}/cert.pem`) },
  (req, res) => {
    writeFileSync(`${dir}/hit.json`, JSON.stringify({
      method: req.method, url: req.url, session: req.headers['x-amux-session'] || '',
    }));
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: true, touched: [] }));
  },
);
srv.listen(0, '127.0.0.1', () => console.log(srv.address().port));
JS

node "$TMP/server.mjs" "$TMP" > "$TMP/port" 2>"$TMP/srv.err" &
SRV_PID=$!
disown %% 2>/dev/null || true
PORT=""
for _ in $(seq 1 100); do
  PORT=$(head -1 "$TMP/port" 2>/dev/null || true)
  [ -n "$PORT" ] && break
  sleep 0.05
done
if [ -z "$PORT" ]; then
  echo "FAIL: the TLS recorder never reported a port"
  head -5 "$TMP/srv.err" || true
  exit 1
fi

echo "cdp.mjs keepalive reaches a self-signed amux (AMUX-4685)"
echo

# `list` needs no Chrome to reach the keepalive: the keepalive is sent before any
# CDP connection is attempted, so the command failing to find a browser is fine
# and expected here. What is asserted is that the request ARRIVED.
rm -f "$TMP/hit.json"
AMUX_URL="https://127.0.0.1:$PORT" AMUX_SESSION="cdptest" CDP_PORT=1 \
  node skills/chrome-cdp/scripts/cdp.mjs list >/dev/null 2>&1 || true

if [ -s "$TMP/hit.json" ]; then PASS=$((PASS+1)); else
  FAIL=$((FAIL+1))
  echo "  FAIL  the keepalive never arrived over TLS (this is the fetch/self-signed bug)"
fi
if [ -s "$TMP/hit.json" ]; then
  got_url=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["url"])' "$TMP/hit.json")
  got_method=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["method"])' "$TMP/hit.json")
  got_session=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["session"])' "$TMP/hit.json")
  [ "$got_url" = "/api/browser/keepalive" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "  FAIL  wrong path: $got_url"; }
  [ "$got_method" = "POST" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "  FAIL  wrong method: $got_method"; }
  [ "$got_session" = "cdptest" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "  FAIL  session header not sent: '$got_session'"; }
fi

# THE DISCRIMINATION. `help` is not driving a browser, so it must claim nothing.
# Without this the keepalive could fire on every invocation and still look right.
rm -f "$TMP/hit.json"
AMUX_URL="https://127.0.0.1:$PORT" AMUX_SESSION="cdptest" \
  node skills/chrome-cdp/scripts/cdp.mjs help >/dev/null 2>&1 || true
if [ -s "$TMP/hit.json" ]; then
  FAIL=$((FAIL+1)); echo "  FAIL  a help invocation claimed a browser was in use"
else PASS=$((PASS+1)); fi

# NO AMUX_URL MUST NOT BREAK THE COMMAND. A CDP driver outside amux has no server
# to tell, and the keepalive is best-effort by design.
rm -f "$TMP/hit.json"
if env -u AMUX_URL -u AMUX_API node skills/chrome-cdp/scripts/cdp.mjs help >/dev/null 2>&1; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1)); echo "  FAIL  cdp.mjs help failed with no AMUX_URL set"
fi

echo
echo "  population: $((PASS + FAIL)) cells, $FAIL failing"
if [ "$FAIL" -gt 0 ]; then
  echo "FAIL ($FAIL of $((PASS + FAIL)) cells)"
  exit 1
fi
echo "PASS ($PASS cells)"
