#!/usr/bin/env bash
set -euo pipefail

# Generate a QR code from a WireGuard .conf file for iOS import.
# The WireGuard app on iOS can scan the QR code to import the tunnel config.
#
# Prerequisites (any one):
#   - qrencode (Linux/macOS via brew/apt/dnf)
#   - Python 3 with 'qrcode' package (pip3 install qrcode)
#
# Usage:
#   ./client/ios_qr.sh --config client/output/wg_phone.conf
#   ./client/ios_qr.sh --config client/output/wg_phone.conf --output phone_qr.png

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

CONFIG_FILE=""
OUTPUT_PNG=""
TERMINAL_ONLY=false

usage() {
    cat <<EOF
Usage: $0 --config CONFIG_FILE [OPTIONS]

Required:
  --config FILE    WireGuard client .conf file

Options:
  --output FILE    Save QR code as PNG image (requires qrencode or pillow)
  --terminal       Print QR in terminal only (skip PNG output)
  --help           Show this help

iOS setup:
  1. Install "WireGuard" from the App Store
  2. Tap "+" → "Create from QR code"
  3. Scan the QR code displayed or printed here
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --config)   CONFIG_FILE="$2"; shift 2 ;;
        --output)   OUTPUT_PNG="$2"; shift 2 ;;
        --terminal) TERMINAL_ONLY=true; shift ;;
        --help)     usage; exit 0 ;;
        *)          error "Unknown option: $1" ;;
    esac
done

[[ -n "$CONFIG_FILE" ]] || error "--config is required"
[[ -f "$CONFIG_FILE" ]] || error "Config file not found: $CONFIG_FILE"

CONFIG_CONTENT=$(cat "$CONFIG_FILE")

# ---------- Try to find a QR encoder ----------
generate_terminal_qr() {
    # Method 1: qrencode (most reliable, smallest output)
    if command -v qrencode &>/dev/null; then
        echo "$CONFIG_CONTENT" | qrencode -t UTF8 -o -
        return 0
    fi

    # Method 2: Python qrcode with terminal output
    if python3 -c "import qrcode" 2>/dev/null; then
        python3 - <<PYEOF
import qrcode, sys
content = sys.stdin.read()
qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_L)
qr.add_data(content)
qr.make(fit=True)
qr.print_ascii(invert=True)
PYEOF <<< "$CONFIG_CONTENT"
        return 0
    fi

    # Method 3: wg showconf piped to qrencode (for reading server configs)
    return 1
}

generate_png_qr() {
    local out="$1"
    # Method 1: qrencode → PNG
    if command -v qrencode &>/dev/null; then
        echo "$CONFIG_CONTENT" | qrencode -t PNG -o "$out" -s 8
        return 0
    fi
    # Method 2: Python qrcode + Pillow
    if python3 -c "import qrcode, PIL" 2>/dev/null; then
        python3 - "$out" <<PYEOF
import qrcode, sys
content = open("$CONFIG_FILE").read()
img = qrcode.make(content)
img.save(sys.argv[1])
PYEOF
        return 0
    fi
    return 1
}

install_hint() {
    echo ""
    warn "No QR code generator found. Install one:"
    echo "  macOS : brew install qrencode"
    echo "  Ubuntu: sudo apt install qrencode"
    echo "  RHEL  : sudo dnf install qrencode"
    echo "  Python: pip3 install qrcode[pil]"
    echo ""
    echo "Or use the WireGuard App for macOS (File → Export tunnel) to generate QR from an existing tunnel."
}

# ---------- Terminal QR ----------
echo ""
echo "  ┌─────────────────────────────────────────┐"
echo "  │  WireGuard QR Code for iOS              │"
echo "  │  Config: $(basename "$CONFIG_FILE")     │"
echo "  └─────────────────────────────────────────┘"
echo ""

if ! generate_terminal_qr; then
    install_hint
    # Fall through to check if PNG is requested
fi

# ---------- PNG output ----------
if ! $TERMINAL_ONLY; then
    if [[ -z "$OUTPUT_PNG" ]]; then
        CONF_BASENAME=$(basename "${CONFIG_FILE%.conf}")
        OUTPUT_PNG="$(dirname "$CONFIG_FILE")/${CONF_BASENAME}_ios_qr.png"
    fi

    if generate_png_qr "$OUTPUT_PNG"; then
        success "QR code PNG saved: $OUTPUT_PNG"
        echo ""
        echo "  Send this PNG to your iPhone via:"
        echo "    AirDrop, iCloud Drive, WeChat, or any file transfer app"
        echo "    Then open with WireGuard App → tap 'Create from QR code'"
    else
        warn "Could not generate PNG. Install qrencode or pip3 install qrcode[pil]"
    fi
fi

echo ""
echo "  iOS setup steps:"
echo "  1. Install 'WireGuard' from App Store (it's free)"
echo "  2. Tap '+' button → 'Create from QR code'"
echo "  3. Scan the QR code above"
echo "  4. Allow VPN configuration when prompted"
echo "  5. Toggle the tunnel ON — only overseas traffic routes via Singapore"
echo ""
success "Done. Scan the QR code with your iPhone."
echo ""
