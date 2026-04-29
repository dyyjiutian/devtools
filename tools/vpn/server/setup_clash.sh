#!/usr/bin/env bash
set -euo pipefail

# Set up Clash Meta (mihomo) as a transparent proxy on the WireGuard server.
#
# Architecture:
#   WireGuard client traffic (TCP 443/80)
#     → iptables TPROXY (mangle PREROUTING on wg0)
#     → mihomo (tproxy port 7893)
#     → claude.ai / anthropic → residential static proxy (198.51.100.50)
#     → everything else       → DIRECT (ECS public IP)
#
# Usage:
#   sudo ./server/setup_clash.sh
#   sudo ./server/setup_clash.sh --update-proxy "user:pass@host:port"
#   sudo ./server/setup_clash.sh --clean

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${CYAN}=== $* ===${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASH_CONF_SRC="$SCRIPT_DIR/clash/config.yaml"

MIHOMO_DIR="/etc/mihomo"
MIHOMO_BIN="/usr/local/bin/mihomo"
MIHOMO_SERVICE="mihomo"
TPROXY_PORT=7893
REDIR_PORT=7892
WG_IFACE="wg0"
TPROXY_MARK="0x1"
TPROXY_TABLE="100"

CLEAN=false
UPDATE_PROXY=""
INTERNAL_CMD=""

usage() {
    cat <<EOF
Usage: sudo $0 [OPTIONS]

Options:
  --update-proxy USER:PASS@HOST:PORT   Update residential proxy credentials in config
  --clean                              Stop mihomo and remove tproxy rules
  --help                               Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --update-proxy)  UPDATE_PROXY="$2"; shift 2 ;;
        --clean)         CLEAN=true; shift ;;
        --apply-tproxy)  INTERNAL_CMD="apply"; shift ;;
        --remove-tproxy) INTERNAL_CMD="remove"; shift ;;
        --help)          usage; exit 0 ;;
        *)               error "Unknown option: $1" ;;
    esac
done

[[ $EUID -eq 0 ]] || error "Run as root: sudo $0"

# ============================================================
# Clean mode
# ============================================================
if $CLEAN; then
    step "Stopping mihomo and removing redirect rules"
    systemctl stop  "$MIHOMO_SERVICE" 2>/dev/null || true
    systemctl disable "$MIHOMO_SERVICE" 2>/dev/null || true

    # Remove TPROXY rules and policy routing
    iptables -t mangle -D PREROUTING -i "$WG_IFACE" -p tcp --dport 443 -j MIHOMO_TPROXY 2>/dev/null || true
    iptables -t mangle -D PREROUTING -i "$WG_IFACE" -p tcp --dport 80  -j MIHOMO_TPROXY 2>/dev/null || true
    iptables -t mangle -F MIHOMO_TPROXY 2>/dev/null || true
    iptables -t mangle -X MIHOMO_TPROXY 2>/dev/null || true
    ip rule del fwmark "$TPROXY_MARK" table "$TPROXY_TABLE" 2>/dev/null || true
    ip route del local default dev lo table "$TPROXY_TABLE" 2>/dev/null || true
    # Remove stale NAT rules
    WG_SERVER_IP=$(ip -4 addr show "$WG_IFACE" 2>/dev/null | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+' | head -1)
    iptables -t nat -D PREROUTING -i "$WG_IFACE" -p tcp --dport 443 -j REDIRECT --to-ports "$REDIR_PORT" 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "$WG_IFACE" -p tcp --dport 80  -j REDIRECT --to-ports "$REDIR_PORT" 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "$WG_IFACE" -p tcp --dport 443 -j DNAT --to-destination "${WG_SERVER_IP}:${REDIR_PORT}" 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "$WG_IFACE" -p tcp --dport 80  -j DNAT --to-destination "${WG_SERVER_IP}:${REDIR_PORT}" 2>/dev/null || true

    # Remove legacy TPROXY rules if present
    iptables -t mangle -D PREROUTING -i "$WG_IFACE" -p tcp --dport 443 -j MIHOMO_TPROXY 2>/dev/null || true
    iptables -t mangle -D PREROUTING -i "$WG_IFACE" -p tcp --dport 80  -j MIHOMO_TPROXY 2>/dev/null || true
    iptables -t mangle -F MIHOMO_TPROXY 2>/dev/null || true
    iptables -t mangle -X MIHOMO_TPROXY 2>/dev/null || true
    ip rule del fwmark 0x1 table 100 2>/dev/null || true
    ip route del local default dev lo table 100 2>/dev/null || true

    rm -f /etc/systemd/system/${MIHOMO_SERVICE}.service
    systemctl daemon-reload
    success "mihomo and redirect rules removed"
    exit 0
fi

# ============================================================
# Download mihomo binary
# ============================================================
step "Installing mihomo (Clash Meta)"

ARCH=$(uname -m)
case $ARCH in
    x86_64)  MIHOMO_ARCH="amd64" ;;
    aarch64) MIHOMO_ARCH="arm64" ;;
    *)        error "Unsupported architecture: $ARCH" ;;
esac

if [[ -f "$MIHOMO_BIN" ]] && "$MIHOMO_BIN" -v &>/dev/null; then
    CURRENT_VER=$("$MIHOMO_BIN" -v 2>&1 | grep -oP 'v[\d.]+' | head -1)
    info "mihomo already installed: $CURRENT_VER"
else
    info "Fetching latest mihomo release..."
    LATEST=$(curl -fsSL --connect-timeout 15 \
        "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" \
        | grep '"tag_name"' | grep -oP 'v[\d.]+' | head -1)
    [[ -n "$LATEST" ]] || error "Failed to fetch mihomo release version"
    info "Downloading mihomo $LATEST for linux-$MIHOMO_ARCH..."

    TMP=$(mktemp -d)
    trap "rm -rf $TMP" EXIT
    curl -fsSL --connect-timeout 30 --retry 3 \
        "https://github.com/MetaCubeX/mihomo/releases/download/${LATEST}/mihomo-linux-${MIHOMO_ARCH}-${LATEST}.gz" \
        -o "$TMP/mihomo.gz"
    gunzip "$TMP/mihomo.gz"
    install -m 755 "$TMP/mihomo" "$MIHOMO_BIN"
    success "mihomo $LATEST installed → $MIHOMO_BIN"
fi

# ============================================================
# Install config
# ============================================================
step "Installing mihomo config"
mkdir -p "$MIHOMO_DIR"

if [[ -f "$CLASH_CONF_SRC" ]]; then
    install -m 640 "$CLASH_CONF_SRC" "$MIHOMO_DIR/config.yaml"
    success "Config installed from $CLASH_CONF_SRC"
else
    error "Config template not found: $CLASH_CONF_SRC"
fi

# ============================================================
# Update proxy credentials (if --update-proxy given)
# ============================================================
if [[ -n "$UPDATE_PROXY" ]]; then
    step "Updating proxy credentials"
    # Expected format: user:pass@host:port
    PROXY_USER=$(echo "$UPDATE_PROXY" | sed 's/:.*@.*//' )
    PROXY_PASS=$(echo "$UPDATE_PROXY" | sed 's/^[^:]*://; s/@[^@]*$//')
    PROXY_HOST=$(echo "$UPDATE_PROXY" | sed 's/.*@//; s/:.*//')
    PROXY_PORT=$(echo "$UPDATE_PROXY" | sed 's/.*://')

    sed -i "s|server: .*|server: $PROXY_HOST|" "$MIHOMO_DIR/config.yaml"
    sed -i "s|port: [0-9]*$|port: $PROXY_PORT|" "$MIHOMO_DIR/config.yaml"
    sed -i "s|username: .*|username: \"$PROXY_USER\"|" "$MIHOMO_DIR/config.yaml"
    sed -i "s|password: .*|password: \"$PROXY_PASS\"|" "$MIHOMO_DIR/config.yaml"
    success "Proxy credentials updated"
fi

# ============================================================
# Create systemd service
# ============================================================
step "Creating systemd service (${MIHOMO_SERVICE})"
cat > "/etc/systemd/system/${MIHOMO_SERVICE}.service" <<UNIT
[Unit]
Description=Clash Meta (mihomo) transparent proxy
After=network.target wg-quick@wg0.service
Wants=wg-quick@wg0.service

[Service]
Type=simple
ExecStart=${MIHOMO_BIN} -d ${MIHOMO_DIR}
ExecStartPost=/bin/bash -c '${SCRIPT_DIR}/setup_clash.sh --apply-tproxy'
ExecStop=/bin/bash -c '${SCRIPT_DIR}/setup_clash.sh --remove-tproxy'
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
UNIT

# ============================================================
# Apply tproxy rules function (also called via systemd ExecStartPost)
# ============================================================
apply_tproxy() {
    step "Configuring iptables REDIRECT rules"

    # Remove legacy TPROXY rules/chains if present
    iptables -t mangle -D PREROUTING -i "$WG_IFACE" -p tcp --dport 443 -j MIHOMO_TPROXY 2>/dev/null || true
    iptables -t mangle -D PREROUTING -i "$WG_IFACE" -p tcp --dport 80  -j MIHOMO_TPROXY 2>/dev/null || true
    iptables -t mangle -F MIHOMO_TPROXY 2>/dev/null || true
    iptables -t mangle -X MIHOMO_TPROXY 2>/dev/null || true
    ip rule del fwmark 0x1 table 100 2>/dev/null || true
    ip route del local default dev lo table 100 2>/dev/null || true

    # Policy routing: fwmark → loopback (required for TPROXY delivery)
    if ! ip rule show | grep -q "fwmark $TPROXY_MARK lookup $TPROXY_TABLE"; then
        ip rule add fwmark "$TPROXY_MARK" table "$TPROXY_TABLE" priority 100
    fi
    if ! ip route show table "$TPROXY_TABLE" 2>/dev/null | grep -q "local default"; then
        ip route add local default dev lo table "$TPROXY_TABLE"
    fi

    # Clean up any stale REDIRECT/DNAT rules from previous attempts
    WG_SERVER_IP=$(ip -4 addr show "$WG_IFACE" 2>/dev/null | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+' | head -1)
    iptables -t nat -D PREROUTING -i "$WG_IFACE" -p tcp --dport 443 -j REDIRECT --to-ports "$REDIR_PORT" 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "$WG_IFACE" -p tcp --dport 80  -j REDIRECT --to-ports "$REDIR_PORT" 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "$WG_IFACE" -p tcp --dport 443 -j DNAT --to-destination "${WG_SERVER_IP}:${REDIR_PORT}" 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "$WG_IFACE" -p tcp --dport 80  -j DNAT --to-destination "${WG_SERVER_IP}:${REDIR_PORT}" 2>/dev/null || true

    # TPROXY chain: --on-ip 127.0.0.1 explicitly targets mihomo's loopback socket
    iptables -t mangle -N MIHOMO_TPROXY 2>/dev/null || iptables -t mangle -F MIHOMO_TPROXY
    iptables -t mangle -A MIHOMO_TPROXY -p tcp -j TPROXY \
        --on-ip 127.0.0.1 --on-port "$TPROXY_PORT" --tproxy-mark "$TPROXY_MARK"

    iptables -t mangle -D PREROUTING -i "$WG_IFACE" -p tcp --dport 443 -j MIHOMO_TPROXY 2>/dev/null || true
    iptables -t mangle -D PREROUTING -i "$WG_IFACE" -p tcp --dport 80  -j MIHOMO_TPROXY 2>/dev/null || true
    iptables -t mangle -A PREROUTING -i "$WG_IFACE" -p tcp --dport 443 -j MIHOMO_TPROXY
    iptables -t mangle -A PREROUTING -i "$WG_IFACE" -p tcp --dport 80  -j MIHOMO_TPROXY

    success "TPROXY rules applied (wg0 TCP 80/443 → 127.0.0.1:${TPROXY_PORT} [mihomo])"
}

remove_tproxy() {
    iptables -t nat -D PREROUTING -i "$WG_IFACE" -p tcp --dport 443 -j REDIRECT --to-ports "$REDIR_PORT" 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "$WG_IFACE" -p tcp --dport 80  -j REDIRECT --to-ports "$REDIR_PORT" 2>/dev/null || true
    # Legacy TPROXY cleanup
    iptables -t mangle -F MIHOMO_TPROXY 2>/dev/null || true
    iptables -t mangle -X MIHOMO_TPROXY 2>/dev/null || true
    ip rule del fwmark 0x1 table 100 2>/dev/null || true
    ip route del local default dev lo table 100 2>/dev/null || true
}

# Allow systemd ExecStartPost/ExecStop to call this script directly
if [[ "$INTERNAL_CMD" == "apply"  ]]; then apply_tproxy; exit 0; fi
if [[ "$INTERNAL_CMD" == "remove" ]]; then remove_tproxy; exit 0; fi

# ============================================================
# Apply tproxy rules now (initial setup)
# ============================================================
apply_tproxy

# ============================================================
# Start service
# ============================================================
step "Starting mihomo service"
systemctl daemon-reload
systemctl enable --now "$MIHOMO_SERVICE"
sleep 2
systemctl is-active "$MIHOMO_SERVICE" > /dev/null \
    && success "mihomo is running" \
    || error "mihomo failed to start — check: journalctl -u $MIHOMO_SERVICE -n 50"

# ============================================================
# Verify proxy connectivity
# ============================================================
step "Verifying residential proxy connectivity"
if curl -fsSL --connect-timeout 10 \
    -x "http://REDACTED-PROXY-USER:REDACTED-PROXY-PASS@198.51.100.50:44231" \
    "https://ipv4.icanhazip.com" > /tmp/residential_ip.txt 2>/dev/null; then
    RESIDENTIAL_IP=$(cat /tmp/residential_ip.txt)
    success "Residential proxy OK — outbound IP: $RESIDENTIAL_IP"
else
    warn "Could not verify residential proxy. Check credentials or network."
fi

# ============================================================
# Summary
# ============================================================
echo ""
success "================================================"
success " mihomo transparent proxy setup complete!"
success "================================================"
echo ""
echo "  Config      : $MIHOMO_DIR/config.yaml"
echo "  Binary      : $MIHOMO_BIN"
echo "  Tproxy port : $TPROXY_PORT"
echo ""
  echo "  Traffic routing (from WireGuard clients):"
echo "    claude.ai / anthropic.com  → residential static proxy (198.51.100.50)"
echo "    openai.com / chatgpt.com   → residential static proxy (198.51.100.50)"
echo "    everything else            → ECS direct"
echo ""
echo "  TPROXY port     : $TPROXY_PORT (--on-ip 127.0.0.1, wg0 TCP 80/443)"
echo ""
echo "  Useful commands:"
echo "    Status  : systemctl status $MIHOMO_SERVICE"
echo "    Logs    : journalctl -u $MIHOMO_SERVICE -f"
echo "    Reload  : systemctl restart $MIHOMO_SERVICE"
echo "    Remove  : sudo $0 --clean"
echo ""
echo "  Add more domains: edit $MIHOMO_DIR/config.yaml → rules section"
echo "  then: systemctl restart $MIHOMO_SERVICE"
echo ""
