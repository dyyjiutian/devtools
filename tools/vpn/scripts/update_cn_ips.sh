#!/usr/bin/env bash
set -euo pipefail

# Download China IP CIDR list from APNIC
# Output: one CIDR per line to stdout (or to a file)

APNIC_URL="http://ftp.apnic.net/stats/apnic/delegated-apnic-latest"
CACHE_DIR="${CACHE_DIR:-/tmp/wg-vpn}"
CACHE_FILE="$CACHE_DIR/delegated-apnic-latest"
CN_CIDR_FILE="$CACHE_DIR/cn_cidrs.txt"
MAX_AGE_HOURS="${MAX_AGE_HOURS:-24}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}[INFO]${NC}  $*" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*" >&2; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*" >&2; }

usage() {
    cat <<EOF >&2
Usage: $0 [--output FILE] [--force] [--help]

Download China IP CIDR list from APNIC and write to stdout or file.

Options:
  --output FILE   Write CIDRs to FILE instead of stdout
  --force         Force re-download even if cache is fresh
  --help          Show this help
EOF
}

OUTPUT_FILE=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --output) OUTPUT_FILE="$2"; shift 2 ;;
        --force)  FORCE=true; shift ;;
        --help)   usage; exit 0 ;;
        *)        echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

mkdir -p "$CACHE_DIR"

# Check cache freshness
is_cache_stale() {
    [[ ! -f "$CACHE_FILE" ]] && return 0
    local age_secs=$(( $(date +%s) - $(date -r "$CACHE_FILE" +%s 2>/dev/null || echo 0) ))
    local max_secs=$(( MAX_AGE_HOURS * 3600 ))
    [[ $age_secs -gt $max_secs ]]
}

if $FORCE || is_cache_stale; then
    info "Downloading APNIC delegation data..."
    if command -v curl &>/dev/null; then
        curl -fsSL --connect-timeout 15 --retry 3 -o "$CACHE_FILE" "$APNIC_URL"
    elif command -v wget &>/dev/null; then
        wget -q --timeout=15 --tries=3 -O "$CACHE_FILE" "$APNIC_URL"
    else
        echo "Error: curl or wget required" >&2; exit 1
    fi
    ok "Downloaded: $(wc -l < "$CACHE_FILE") lines"
else
    info "Using cached data (< ${MAX_AGE_HOURS}h old): $CACHE_FILE"
fi

# Parse: extract CN IPv4 blocks, convert start+count to CIDR
info "Parsing China IPv4 blocks..."
awk -F'|' '
$1=="apnic" && $2=="CN" && $3=="ipv4" {
    ip=$4; count=$5+0
    # Convert count to prefix length: prefix = 32 - log2(count)
    n=count; bits=0
    while (n>1) { n=n/2; bits++ }
    print ip "/" (32-bits)
}' "$CACHE_FILE" > "$CN_CIDR_FILE"

CN_COUNT=$(wc -l < "$CN_CIDR_FILE")
ok "Found ${CN_COUNT} China IPv4 CIDR blocks"

if [[ -n "$OUTPUT_FILE" ]]; then
    cp "$CN_CIDR_FILE" "$OUTPUT_FILE"
    ok "Written to: $OUTPUT_FILE"
else
    cat "$CN_CIDR_FILE"
fi
