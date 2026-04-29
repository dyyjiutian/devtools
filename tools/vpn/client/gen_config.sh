#!/usr/bin/env bash
set -euo pipefail

# Generate WireGuard client config with split tunneling (non-China IPs only).
# Must be run on the WireGuard SERVER so it can read the server public key
# and append the client [Peer] block to /etc/wireguard/wg0.conf.
#
# Usage:
#   sudo ./client/gen_config.sh --name macbook --server-ip 1.2.3.4
#   sudo ./client/gen_config.sh --name phone   --server-ip 1.2.3.4 --client-ip 10.8.0.3
#   ./client/gen_config.sh --name test --server-ip 1.2.3.4 --no-server-update

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${CYAN}=== $* ===${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPN_ROOT="$(dirname "$SCRIPT_DIR")"

# Prefer a Python 3.9+ interpreter (system root may have older Python)
PYTHON3=$(command -v python3.9 2>/dev/null || command -v python3.11 2>/dev/null || \
          command -v python3.12 2>/dev/null || \
          { python3 -c "import sys; sys.exit(0 if sys.version_info >= (3,9) else 1)" 2>/dev/null && echo "python3"; } || \
          echo "/opt/aiext/bin/python3")
PYTHON3="${PYTHON3:-python3}"

WG_DIR="/etc/wireguard"
WG_IFACE="wg0"
WG_PORT="51820"
WG_SERVER_VPN_IP="10.8.0.1"
DNS="8.8.8.8"

CLIENT_NAME=""
SERVER_IP=""
CLIENT_IP=""     # auto-assigned if empty
NO_SERVER_UPDATE=false
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/output}"
FORCE_REFRESH_IPS=false

usage() {
    cat <<EOF
Usage: sudo $0 --name NAME --server-ip SERVER_IP [OPTIONS]

Required:
  --name NAME         Client name (e.g. macbook, phone, desktop)
  --server-ip IP      Public IP of the WireGuard server (Singapore ECS)

Options:
  --client-ip IP      Tunnel IP for this client (default: auto from 10.8.0.2+)
  --port PORT         Server WireGuard port (default: 51820)
  --dns DNS           DNS server in tunnel (default: 8.8.8.8)
  --no-server-update  Generate config only; don't modify server wg0.conf
  --refresh-ips       Force re-download of China IP list
  --output-dir DIR    Directory to write client configs (default: client/output/)
  --help              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --name)             CLIENT_NAME="$2"; shift 2 ;;
        --server-ip)        SERVER_IP="$2"; shift 2 ;;
        --client-ip)        CLIENT_IP="$2"; shift 2 ;;
        --port)             WG_PORT="$2"; shift 2 ;;
        --dns)              DNS="$2"; shift 2 ;;
        --no-server-update) NO_SERVER_UPDATE=true; shift ;;
        --refresh-ips)      FORCE_REFRESH_IPS=true; shift ;;
        --output-dir)       OUTPUT_DIR="$2"; shift 2 ;;
        --help)             usage; exit 0 ;;
        *)                  error "Unknown option: $1" ;;
    esac
done

[[ -n "$CLIENT_NAME" ]] || error "--name is required"
[[ -n "$SERVER_IP"   ]] || error "--server-ip is required"

# Sanitize name for filename
SAFE_NAME=$(echo "$CLIENT_NAME" | tr ' /' '_' | tr -cd '[:alnum:]_-')

# ---------- Auto-assign client IP ----------
step "Determining client IP"
if [[ -z "$CLIENT_IP" ]]; then
    if [[ $EUID -eq 0 ]] && [[ -f "$WG_DIR/$WG_IFACE.conf" ]]; then
        # Find highest existing .X/32 in server config
        LAST_OCTET=$(grep -oP '10\.8\.0\.\K\d+(?=/32)' "$WG_DIR/$WG_IFACE.conf" 2>/dev/null | sort -n | tail -1)
        NEXT_OCTET=$(( ${LAST_OCTET:-1} + 1 ))
        [[ $NEXT_OCTET -le 254 ]] || error "Subnet exhausted (max 254 clients)"
        CLIENT_IP="10.8.0.${NEXT_OCTET}"
    else
        # Default if can't read server conf
        CLIENT_IP="10.8.0.2"
        warn "Cannot auto-detect next IP (need root + server conf); using $CLIENT_IP"
    fi
fi
info "Client VPN IP: $CLIENT_IP"

# ---------- Generate client keypair ----------
step "Generating client keypair for '$CLIENT_NAME'"
CLIENT_PRIVATE=$(wg genkey)
CLIENT_PUBLIC=$(echo "$CLIENT_PRIVATE" | wg pubkey)
success "Client public key: $CLIENT_PUBLIC"

# ---------- Read server public key ----------
step "Reading server public key"
SERVER_PUBLIC_FILE="$WG_DIR/server_public.key"
if [[ -f "$SERVER_PUBLIC_FILE" ]]; then
    SERVER_PUBLIC=$(cat "$SERVER_PUBLIC_FILE")
    info "Server public key: $SERVER_PUBLIC"
elif $NO_SERVER_UPDATE; then
    warn "Server public key file not found ($SERVER_PUBLIC_FILE)"
    warn "You must fill in <SERVER_PUBLIC_KEY> manually in the generated config"
    SERVER_PUBLIC="<SERVER_PUBLIC_KEY>"
else
    error "Server public key not found at $SERVER_PUBLIC_FILE. Run server/setup.sh first, or use --no-server-update."
fi

# ---------- Build AllowedIPs (CN complement) ----------
step "Building split-tunnel AllowedIPs (non-China IP ranges)"
CACHE_DIR="/tmp/wg-vpn"
CN_CIDR_FILE="$CACHE_DIR/cn_cidrs.txt"

REFRESH_FLAG=""
$FORCE_REFRESH_IPS && REFRESH_FLAG="--force"

# Download/update China IPs (write to file, not stdout)
bash "$VPN_ROOT/scripts/update_cn_ips.sh" --output "$CN_CIDR_FILE" $REFRESH_FLAG

CN_COUNT=$(wc -l < "$CN_CIDR_FILE")
info "China CIDR blocks: $CN_COUNT"

# Compute complement — O(n log n), typically <2s for 8000+ CIDRs
# IMPORTANT: exclude the server's endpoint IP to prevent routing loop.
# (If the server IP is in AllowedIPs, WireGuard packets to the server
#  get routed back into the tunnel → loop → total network blackout.)
info "Computing non-China AllowedIPs (this takes ~2s)..."
ALLOWED_IPS=$("$PYTHON3" "$VPN_ROOT/scripts/cn_cidr_complement.py" \
    --cn-file "$CN_CIDR_FILE" \
    --exclude "${SERVER_IP}" \
    --wg-format --stats 2>/dev/null)

ALLOWED_COUNT=$(echo "$ALLOWED_IPS" | tr ',' '\n' | wc -l)
success "AllowedIPs blocks: $ALLOWED_COUNT (overseas/non-China routes)"

# ---------- Write client .conf ----------
step "Writing client config"
mkdir -p "$OUTPUT_DIR"
CLIENT_CONF="$OUTPUT_DIR/wg_${SAFE_NAME}.conf"

cat > "$CLIENT_CONF" <<EOF
# WireGuard client config: ${CLIENT_NAME}
# Generated: $(date -u +"%Y-%m-%d %H:%M UTC")
# Split tunnel: only non-China traffic routes through VPN

[Interface]
Address    = ${CLIENT_IP}/24
PrivateKey = ${CLIENT_PRIVATE}
DNS        = ${DNS}
MTU        = 1420

[Peer]
# Singapore ECS WireGuard server
PublicKey           = ${SERVER_PUBLIC}
Endpoint            = ${SERVER_IP}:${WG_PORT}
AllowedIPs          = ${ALLOWED_IPS}
PersistentKeepalive = 25
EOF

chmod 600 "$CLIENT_CONF"
success "Client config written: $CLIENT_CONF"

# ---------- Append [Peer] to server wg0.conf ----------
if ! $NO_SERVER_UPDATE; then
    step "Appending [Peer] to server /etc/wireguard/${WG_IFACE}.conf"
    [[ $EUID -eq 0 ]] || error "Need root to update server config. Use --no-server-update to skip."

    PEER_BLOCK="
[Peer]
# Name: ${CLIENT_NAME}
PublicKey  = ${CLIENT_PUBLIC}
AllowedIPs = ${CLIENT_IP}/32"

    # Remove existing peer with same Name to prevent duplicates on re-generation
    if grep -q "# Name: ${CLIENT_NAME}$" "$WG_DIR/$WG_IFACE.conf" 2>/dev/null; then
        warn "Replacing existing peer '${CLIENT_NAME}' in server config"
        # Delete the [Peer] block for this client (from [Peer] line to next blank line or EOF)
        "$PYTHON3" - "$WG_DIR/$WG_IFACE.conf" "${CLIENT_NAME}" <<'PYEOF'
import sys, re
conf_file, name = sys.argv[1], sys.argv[2]
with open(conf_file) as f:
    content = f.read()
# Remove peer block that contains "# Name: <name>"
pattern = r'\n\[Peer\][^\[]*# Name: ' + re.escape(name) + r'[^\[]*'
content = re.sub(pattern, '', content)
with open(conf_file, 'w') as f:
    f.write(content)
PYEOF
    fi

    echo "$PEER_BLOCK" >> "$WG_DIR/$WG_IFACE.conf"
    success "Peer added to server config"

    # Hot-reload WireGuard without dropping existing connections
    if systemctl is-active "wg-quick@${WG_IFACE}" &>/dev/null; then
        wg syncconf "$WG_IFACE" <(wg-quick strip "$WG_IFACE")
        success "WireGuard reloaded (no connection drop)"
    else
        warn "wg-quick@${WG_IFACE} is not running; start it with: systemctl start wg-quick@${WG_IFACE}"
    fi
fi

# ---------- Summary ----------
echo ""
success "========================================"
success " Client config ready: ${CLIENT_NAME}"
success "========================================"
echo ""
echo "  Config file  : $CLIENT_CONF"
echo "  Client VPN IP: $CLIENT_IP"
echo "  Split tunnel : non-China IPs → VPN (${ALLOWED_COUNT} routes)"
echo "  DNS          : $DNS (via VPN)"
echo ""
echo "  Install on each platform:"
echo "    macOS  : sudo ./client/setup_macos.sh --config $CLIENT_CONF"
echo "    Linux  : sudo ./client/setup_linux.sh  --config $CLIENT_CONF"
echo "    iOS    : ./client/ios_qr.sh             --config $CLIENT_CONF"
echo ""
