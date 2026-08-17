#!/usr/bin/env bash
# Install the VPN exit node inside the privileged Compose server container.
set -euo pipefail

if [[ ! -f /workspace/network/vpn/exit/setup.sh ]]; then
  echo "pair_server.sh: /workspace/network/vpn/exit/setup.sh missing" >&2
  exit 1
fi

bash /workspace/network/vpn/exit/setup.sh --skip-warp --users=e2euser --port=443

link="$(bash /workspace/network/vpn/exit/manage.sh vless e2euser vpn-exit | grep '^vless://' | head -1 || true)"
if [[ -z "$link" ]]; then
  echo "pair_server.sh: failed to print vless:// link for e2euser" >&2
  exit 1
fi
printf '%s\n' "$link" >/tmp/devtools-e2e-vless.txt
printf 'VLESS_LINK=%s\n' "$link" >/tmp/devtools-e2e-client.env
echo "pair_server.sh: wrote VLESS link for host vpn-exit"
