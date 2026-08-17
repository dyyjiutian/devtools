#!/usr/bin/env bash
# Install the SNI proxy and a local HTTPS origin for E2E traffic.
set -euo pipefail

if [[ ! -f /workspace/network/proxy/server/setup.sh ]]; then
  echo "pair_server.sh: /workspace/network/proxy/server/setup.sh missing" >&2
  exit 1
fi

bash /workspace/network/proxy/server/setup.sh

if ! command -v openssl >/dev/null 2>&1; then
  if command -v yum >/dev/null 2>&1; then
    yum install -y openssl
  else
    apt-get update -qq && apt-get install -y openssl
  fi
fi

openssl req -x509 -newkey rsa:2048 \
  -keyout /tmp/e2e-origin.key -out /tmp/e2e-origin.crt \
  -days 1 -nodes -subj '/CN=e2e.devtools.test' >/dev/null 2>&1
nohup openssl s_server -accept 8443 \
  -cert /tmp/e2e-origin.crt -key /tmp/e2e-origin.key -www \
  >/tmp/e2e-origin.log 2>&1 &
sleep 1

sni_conf="/etc/nginx/stream.d/sni_proxy.conf"
if [[ ! -f "$sni_conf" ]]; then
  echo "pair_server.sh: missing $sni_conf" >&2
  exit 1
fi
if ! grep -q 'e2e.devtools.test' "$sni_conf"; then
  sed -i '/default/i\        e2e.devtools.test                    127.0.0.1:8443;' "$sni_conf"
fi
nginx -t
systemctl reload nginx || systemctl restart nginx

server_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
if [[ -z "$server_ip" ]]; then
  server_ip="$(ip -4 addr show scope global 2>/dev/null | awk '/inet / {print $2; exit}' | cut -d/ -f1 || true)"
fi
if [[ -z "$server_ip" ]]; then
  echo "pair_server.sh: could not determine server IPv4" >&2
  exit 1
fi
printf 'SERVER_IP=%s\n' "$server_ip" >/tmp/devtools-e2e-client.env
echo "pair_server.sh: SNI proxy ready on ${server_ip}:443"
