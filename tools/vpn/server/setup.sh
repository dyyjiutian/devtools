#!/usr/bin/env bash
set -euo pipefail

# WireGuard VPN Server Setup
# Supports: Alibaba Cloud Linux 3 / CentOS 8 / RHEL 8 / Ubuntu 20.04+
# Topology: 10.8.0.1/24 (server), clients 10.8.0.2+

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${CYAN}=== $* ===${NC}"; }

WG_DIR="/etc/wireguard"
WG_IFACE="wg0"
WG_PORT="${WG_PORT:-51820}"
WG_SUBNET="10.8.0.0/24"
WG_SERVER_IP="10.8.0.1"
DRY_RUN=false

usage() {
    cat <<EOF
Usage: sudo $0 [OPTIONS]

Options:
  --port PORT      WireGuard listen port (default: 51820)
  --dry-run        Preview steps without executing
  --help           Show this help

Environment:
  WG_PORT          Listen port (overridden by --port)
EOF
}

detect_iface() {
    ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1
}

run() {
    if $DRY_RUN; then
        echo "  [dry-run] $*"
    else
        "$@"
    fi
}

# ---------- Parse args ----------
while [[ $# -gt 0 ]]; do
    case $1 in
        --port)    WG_PORT="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help)    usage; exit 0 ;;
        *)         error "Unknown option: $1" ;;
    esac
done

[[ $EUID -eq 0 ]] || error "Run as root: sudo $0"

# ---------- Detect OS ----------
step "Detecting OS"
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_LIKE="${ID_LIKE:-}"
else
    OS_ID="unknown"
fi
info "OS: ${PRETTY_NAME:-$OS_ID}"
NET_IFACE=$(detect_iface)
info "Network interface: ${NET_IFACE}"
[[ -n "$NET_IFACE" ]] || error "Cannot detect network interface"

# ---------- Install WireGuard ----------
step "Installing WireGuard"
install_wg_rhel() {
    # Alibaba Cloud Linux ships epel-aliyuncs-release (conflicts with epel-release).
    # Check for either variant before attempting install.
    if ! rpm -q epel-release &>/dev/null && ! rpm -q epel-aliyuncs-release &>/dev/null; then
        run dnf install -y epel-release
    else
        info "EPEL already available ($(rpm -qa | grep -E 'epel.*release' | head -1))"
    fi
    run dnf install -y wireguard-tools
}

install_wg_debian() {
    run apt-get update -qq
    run apt-get install -y wireguard
}

if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" ]] || echo "$OS_LIKE" | grep -q "debian"; then
    install_wg_debian
elif [[ "$OS_ID" =~ ^(centos|rhel|alinux|anolis|fedora)$ ]] || echo "$OS_LIKE" | grep -qE "rhel|fedora|centos"; then
    install_wg_rhel
else
    warn "Unknown OS. Attempting dnf install..."
    run dnf install -y wireguard-tools || run apt-get install -y wireguard
fi
success "WireGuard installed"

# ---------- Generate keys ----------
step "Generating server keys"
run mkdir -p "$WG_DIR"
run chmod 700 "$WG_DIR"

SERVER_PRIVATE_KEY_FILE="$WG_DIR/server_private.key"
SERVER_PUBLIC_KEY_FILE="$WG_DIR/server_public.key"

if [[ -f "$SERVER_PRIVATE_KEY_FILE" ]] && ! $DRY_RUN; then
    warn "Server keys already exist, skipping generation"
    SERVER_PRIVATE=$(cat "$SERVER_PRIVATE_KEY_FILE")
    SERVER_PUBLIC=$(cat "$SERVER_PUBLIC_KEY_FILE")
else
    if $DRY_RUN; then
        SERVER_PRIVATE="<SERVER_PRIVATE_KEY>"
        SERVER_PUBLIC="<SERVER_PUBLIC_KEY>"
        echo "  [dry-run] wg genkey > $SERVER_PRIVATE_KEY_FILE"
        echo "  [dry-run] wg pubkey > $SERVER_PUBLIC_KEY_FILE"
    else
        SERVER_PRIVATE=$(wg genkey)
        SERVER_PUBLIC=$(echo "$SERVER_PRIVATE" | wg pubkey)
        echo "$SERVER_PRIVATE" | install -m 600 /dev/stdin "$SERVER_PRIVATE_KEY_FILE"
        echo "$SERVER_PUBLIC"  > "$SERVER_PUBLIC_KEY_FILE"
    fi
    success "Keys generated"
fi

# ---------- Write wg0.conf ----------
step "Writing /etc/wireguard/${WG_IFACE}.conf"
WG_CONF="$WG_DIR/${WG_IFACE}.conf"

if [[ -f "$WG_CONF" ]] && ! $DRY_RUN; then
    BACKUP="$WG_CONF.bak.$(date +%Y%m%d%H%M%S)"
    warn "Existing config backed up to $BACKUP"
    run cp "$WG_CONF" "$BACKUP"
fi

write_conf() {
# WireGuard conf does NOT support backslash line continuation.
# Each PostUp/PostDown must be a single line or repeated keys.
cat > "$WG_CONF" <<WGCONF
[Interface]
Address    = ${WG_SERVER_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVATE}

# NAT: route client traffic through the server's WAN interface
PostUp   = iptables -t nat -A POSTROUTING -s ${WG_SUBNET} -o ${NET_IFACE} -j MASQUERADE
PostUp   = iptables -A FORWARD -i ${WG_IFACE} -j ACCEPT
PostUp   = iptables -A FORWARD -o ${WG_IFACE} -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s ${WG_SUBNET} -o ${NET_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_IFACE} -j ACCEPT
PostDown = iptables -D FORWARD -o ${WG_IFACE} -j ACCEPT

# -------- Add client [Peer] sections below --------
# Use client/gen_config.sh to generate client keys and append [Peer] sections here.
# Example:
# [Peer]
# # Name: my-macbook
# PublicKey  = <CLIENT_PUBLIC_KEY>
# AllowedIPs = 10.8.0.2/32
WGCONF
    chmod 600 "$WG_CONF"
}

if $DRY_RUN; then
    echo "  [dry-run] write $WG_CONF"
else
    write_conf
    success "Config written: $WG_CONF"
fi

# ---------- IP forwarding ----------
step "Enabling IP forwarding"
run sysctl -w net.ipv4.ip_forward=1

if $DRY_RUN; then
    echo "  [dry-run] persist net.ipv4.ip_forward=1 in /etc/sysctl.d/99-wireguard.conf"
else
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-wireguard.conf
    sysctl -p /etc/sysctl.d/99-wireguard.conf > /dev/null
fi
success "IP forwarding enabled"

# ---------- Start WireGuard ----------
step "Starting WireGuard (wg-quick@${WG_IFACE})"
run systemctl enable --now "wg-quick@${WG_IFACE}"
if ! $DRY_RUN; then
    sleep 1
    systemctl is-active "wg-quick@${WG_IFACE}" > /dev/null && success "WireGuard is running" || error "WireGuard failed to start"
fi

# ---------- Firewall hint ----------
step "Firewall reminder"
if command -v firewall-cmd &>/dev/null && ! $DRY_RUN; then
    if systemctl is-active firewalld &>/dev/null; then
        run firewall-cmd --permanent --add-port="${WG_PORT}/udp"
        run firewall-cmd --permanent --add-masquerade
        run firewall-cmd --reload
        success "firewalld: port ${WG_PORT}/udp opened"
    fi
fi

# ---------- Done ----------
echo ""
success "========================================"
success " WireGuard server setup complete!"
success "========================================"
echo ""
echo "  Server VPN IP  : ${WG_SERVER_IP}"
echo "  Listen port    : ${WG_PORT}/UDP"
echo "  Subnet         : ${WG_SUBNET}"
echo ""
echo "  Server public key:"
if $DRY_RUN; then
    echo "    <SERVER_PUBLIC_KEY>"
else
    echo "    $(cat "$SERVER_PUBLIC_KEY_FILE")"
fi
echo ""
echo "  Next steps:"
echo "  1. Open UDP ${WG_PORT} in Alibaba Cloud ECS security group"
echo "  2. Run 'client/gen_config.sh' on this server to add clients"
echo "  3. Append each client's [Peer] block to /etc/wireguard/wg0.conf"
echo "  4. Reload: wg syncconf wg0 <(wg-quick strip wg0)"
echo ""
