#!/usr/bin/env bash
set -euo pipefail

# WireGuard client setup for Linux
# Supports: Ubuntu 20.04+, Debian 11+, CentOS/RHEL/Alibaba Cloud Linux 3+
#
# Usage:
#   sudo ./client/setup_linux.sh --config client/output/wg_desktop.conf
#   sudo ./client/setup_linux.sh --config client/output/wg_desktop.conf --autostart
#   sudo ./client/setup_linux.sh --clean

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${CYAN}=== $* ===${NC}"; }

CONFIG_FILE=""
WG_IFACE="wg0"
AUTOSTART=false
CLEAN=false

usage() {
    cat <<EOF
Usage: sudo $0 --config CONFIG_FILE [OPTIONS]

Required:
  --config FILE    Path to WireGuard client .conf file

Options:
  --iface NAME     WireGuard interface name (default: wg0)
  --autostart      Enable systemd service for auto-connect on boot
  --clean          Stop tunnel and remove config
  --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --config)    CONFIG_FILE="$2"; shift 2 ;;
        --iface)     WG_IFACE="$2"; shift 2 ;;
        --autostart) AUTOSTART=true; shift ;;
        --clean)     CLEAN=true; shift ;;
        --help)      usage; exit 0 ;;
        *)           error "Unknown option: $1" ;;
    esac
done

[[ $EUID -eq 0 ]] || error "Run as root: sudo $0"

# ---------- Detect OS ----------
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_LIKE="${ID_LIKE:-}"
else
    OS_ID="unknown"; OS_LIKE=""
fi

# ---------- Clean mode ----------
if $CLEAN; then
    step "Removing WireGuard tunnel ($WG_IFACE)"
    if systemctl is-active "wg-quick@${WG_IFACE}" &>/dev/null; then
        systemctl stop "wg-quick@${WG_IFACE}"
    fi
    systemctl disable "wg-quick@${WG_IFACE}" 2>/dev/null || true
    rm -f "/etc/wireguard/${WG_IFACE}.conf"
    success "WireGuard config and service removed"
    exit 0
fi

[[ -n "$CONFIG_FILE" ]] || error "--config is required (or use --clean)"
[[ -f "$CONFIG_FILE" ]] || error "Config file not found: $CONFIG_FILE"

# ---------- Install WireGuard ----------
step "Installing WireGuard"
install_debian() {
    apt-get update -qq
    apt-get install -y wireguard wireguard-tools
}

install_rhel() {
    if ! rpm -q epel-release &>/dev/null; then
        dnf install -y epel-release
    fi
    dnf install -y wireguard-tools
}

if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" ]] || echo "$OS_LIKE" | grep -q "debian"; then
    if ! command -v wg &>/dev/null; then
        install_debian
    else
        success "wireguard-tools already installed"
    fi
elif [[ "$OS_ID" =~ ^(centos|rhel|alinux|anolis|fedora)$ ]] || echo "$OS_LIKE" | grep -qE "rhel|fedora|centos"; then
    if ! command -v wg &>/dev/null; then
        install_rhel
    else
        success "wireguard-tools already installed"
    fi
else
    if ! command -v wg &>/dev/null; then
        warn "Unknown OS. Trying dnf then apt..."
        dnf install -y wireguard-tools 2>/dev/null || apt-get install -y wireguard
    fi
fi
success "WireGuard installed: $(wg --version 2>/dev/null || echo 'ok')"

# ---------- Install config ----------
step "Installing WireGuard config"
WG_CONF_DIR="/etc/wireguard"
mkdir -p "$WG_CONF_DIR"
install -m 600 "$CONFIG_FILE" "$WG_CONF_DIR/${WG_IFACE}.conf"
success "Config installed: $WG_CONF_DIR/${WG_IFACE}.conf"

# ---------- Start tunnel ----------
step "Starting WireGuard tunnel ($WG_IFACE)"
if systemctl is-active "wg-quick@${WG_IFACE}" &>/dev/null; then
    warn "Tunnel already running, restarting..."
    systemctl restart "wg-quick@${WG_IFACE}"
else
    systemctl start "wg-quick@${WG_IFACE}"
fi

sleep 1
systemctl is-active "wg-quick@${WG_IFACE}" > /dev/null && success "Tunnel is up" || error "Tunnel failed to start"

echo ""
wg show "$WG_IFACE"

# ---------- Autostart ----------
if $AUTOSTART; then
    step "Enabling auto-connect on boot"
    systemctl enable "wg-quick@${WG_IFACE}"
    success "Auto-connect enabled (wg-quick@${WG_IFACE})"
fi

# ---------- Summary ----------
echo ""
success "========================================"
success " Linux WireGuard setup complete!"
success "========================================"
echo ""
echo "  Interface  : $WG_IFACE"
echo "  Config     : $WG_CONF_DIR/${WG_IFACE}.conf"
echo ""
echo "  Useful commands:"
echo "    Status    : sudo wg show $WG_IFACE"
echo "    Connect   : sudo systemctl start wg-quick@${WG_IFACE}"
echo "    Disconnect: sudo systemctl stop  wg-quick@${WG_IFACE}"
echo "    Logs      : journalctl -u wg-quick@${WG_IFACE} -f"
echo "    Remove    : sudo $0 --clean"
echo ""
echo "  Verify split tunnel:"
echo "    curl -s https://ifconfig.me         # Singapore IP (overseas traffic)"
echo "    curl -s --max-time 5 http://www.baidu.com -o /dev/null -w '%{http_code}'  # 200 (direct)"
echo ""
