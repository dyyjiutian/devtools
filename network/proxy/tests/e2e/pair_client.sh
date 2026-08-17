#!/usr/bin/env bash
# Configure hosts and fetch a local SNI target through the proxy.
set -euo pipefail

if [[ -z "${SERVER_IP:-}" ]]; then
  echo "pair_client.sh: SERVER_IP is required" >&2
  exit 1
fi
if [[ ! -f /workspace/network/proxy/client/configure.sh ]]; then
  echo "pair_client.sh: configure.sh missing" >&2
  exit 1
fi

bash /workspace/network/proxy/client/configure.sh "$SERVER_IP"

if ! grep -q "${SERVER_IP}  github.com" /etc/hosts; then
  echo "pair_client.sh: github.com hosts entry missing" >&2
  grep -n github.com /etc/hosts >&2 || true
  exit 1
fi
resolved="$(getent hosts github.com 2>/dev/null | awk '{print $1}' || true)"
if [[ "$resolved" != "$SERVER_IP" ]]; then
  echo "pair_client.sh: github.com resolved to '${resolved:-none}', want $SERVER_IP" >&2
  exit 1
fi

printf '%s e2e.devtools.test\n' "$SERVER_IP" >>/etc/hosts

body="$(mktemp)"
code="$(curl -k -sS -o "$body" -w '%{http_code}' \
  --connect-timeout 15 --max-time 30 "https://e2e.devtools.test/" || true)"
if [[ "$code" != "200" ]] && ! grep -qiE 's_server|openssl' "$body"; then
  echo "pair_client.sh: SNI origin failed (http=${code})" >&2
  cat "$body" >&2 || true
  rm -f "$body"
  exit 1
fi
rm -f "$body"
echo "pair_client.sh: hosts configured and SNI proxy reached e2e.devtools.test"
