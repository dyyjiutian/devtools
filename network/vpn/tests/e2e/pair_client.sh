#!/usr/bin/env bash
# Install the VPN client and fetch example.com through SOCKS5.
set -euo pipefail

if [[ -z "${VLESS_LINK:-}" ]]; then
  echo "pair_client.sh: VLESS_LINK is required" >&2
  exit 1
fi
if [[ ! -f /workspace/network/vpn/client/linux_setup.sh ]]; then
  echo "pair_client.sh: /workspace/network/vpn/client/linux_setup.sh missing" >&2
  exit 1
fi

# Docker Desktop ARM + systemd 255 often execs amd64 xray as 255/EXCEPTION
# in ~400us. Install still writes config; start xray directly if the unit fails.
export XRAY_SERVICE_USER="${XRAY_SERVICE_USER:-root}"
if ! bash /workspace/network/vpn/client/linux_setup.sh install --vless="${VLESS_LINK}"; then
  echo "pair_client.sh: systemd start failed; falling back to xray run" >&2
  systemctl cat xray-client >&2 || true
  if [[ ! -x /usr/local/bin/xray || ! -f /usr/local/etc/xray/client.json ]]; then
    echo "pair_client.sh: missing xray binary or client.json" >&2
    exit 1
  fi
  nohup /usr/local/bin/xray run -config /usr/local/etc/xray/client.json \
    >/tmp/xray-client.fallback.log 2>&1 &
  echo $! >/tmp/xray-client.fallback.pid
  sleep 2
  if ! kill -0 "$(cat /tmp/xray-client.fallback.pid)" 2>/dev/null; then
    echo "pair_client.sh: fallback xray exited" >&2
    cat /tmp/xray-client.fallback.log >&2 || true
    exit 1
  fi
fi

ready=false
i=0
while [[ $i -lt 30 ]]; do
  if ss -lnt 2>/dev/null | grep -q ':10808'; then
    ready=true
    break
  fi
  i=$((i + 1))
  sleep 1
done
if ! $ready; then
  echo "pair_client.sh: SOCKS port 10808 is not listening" >&2
  systemctl status xray-client --no-pager >&2 || true
  exit 1
fi

body="$(mktemp)"
code="$(curl -x socks5h://127.0.0.1:10808 -sS -o "$body" -w '%{http_code}' \
  --connect-timeout 15 --max-time 45 https://example.com || true)"
if [[ "$code" != "200" ]]; then
  echo "pair_client.sh: expected HTTP 200 from example.com via SOCKS, got ${code}" >&2
  cat "$body" >&2 || true
  rm -f "$body"
  exit 1
fi
if ! grep -qi 'example' "$body"; then
  echo "pair_client.sh: example.com body did not contain 'example'" >&2
  cat "$body" >&2 || true
  rm -f "$body"
  exit 1
fi
rm -f "$body"
echo "pair_client.sh: SOCKS5 reached https://example.com"
