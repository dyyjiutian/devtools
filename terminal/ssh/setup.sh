#!/usr/bin/env bash
set -euo pipefail

info()    { echo -e "\033[34m[INFO]\033[0m $1"; }
success() { echo -e "\033[32m[OK]\033[0m $1"; }
warn()    { echo -e "\033[33m[WARN]\033[0m $1"; }
error()   { echo -e "\033[31m[ERROR]\033[0m $1"; exit 1; }

SSH_CONFIG="${HOME}/.ssh/config"
SOCKETS_DIR="${HOME}/.ssh/sockets"
MANAGED_START="# === fssh managed: SSH client optimization ==="
MANAGED_END="# === fssh managed end ==="

show_help() {
    cat <<'EOF'
SSH Client Configuration Setup — optimize connections for fssh

Writes the following to ~/.ssh/config (prepended, idempotent):
  ControlMaster auto           — reuse TCP connections to the same host
  ControlPath ~/.ssh/sockets/  — socket directory (created at 700)
  ControlPersist 10m           — keep socket alive 10 min after last session
  ServerAliveInterval 15       — heartbeat every 15 s
  ServerAliveCountMax 3        — disconnect after 3 missed heartbeats (~45 s)
  ConnectTimeout 10            — fail fast on unreachable hosts

Usage:
  ./setup.sh              Apply configuration
  ./setup.sh --dry-run    Preview changes without applying
  ./setup.sh --help       Show this help

To stop a persisted multiplexed connection:
  ssh -O stop <host>
EOF
    exit 0
}

DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h) show_help ;;
        --dry-run|-d) DRY_RUN=true; shift ;;
        *) error "Unknown option: $1. Run ./setup.sh --help for usage." ;;
    esac
done

[[ "$DRY_RUN" == "true" ]] && warn "Dry-run mode: no files will be modified"
echo

# ── Managed block content (uses literal ~ so SSH expands it, not shell) ──
MANAGED_BLOCK="${MANAGED_START}
Host *
    # Connection multiplexing: reuse existing handshake for same host
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%r@%h:%p
    ControlPersist 10m

    # Keepalive: heartbeat every 15 s, disconnect after 3 failures (~45 s)
    ServerAliveInterval 15
    ServerAliveCountMax 3

    # Fail fast on unreachable hosts
    ConnectTimeout 10
${MANAGED_END}"

# ── Create sockets directory ──
if [[ ! -d "$SOCKETS_DIR" ]]; then
    info "Creating ${SOCKETS_DIR} (chmod 700)"
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$SOCKETS_DIR"
        chmod 700 "$SOCKETS_DIR"
        success "Created ${SOCKETS_DIR}"
    else
        echo "  [dry-run] mkdir -p ${SOCKETS_DIR} && chmod 700 ${SOCKETS_DIR}"
    fi
else
    success "${SOCKETS_DIR} already exists"
fi

# ── Check for existing managed block (idempotent) ──
if [[ -f "$SSH_CONFIG" ]] && grep -qF "$MANAGED_START" "$SSH_CONFIG" 2>/dev/null; then
    success "~/.ssh/config already contains fssh managed block — skipping"
    exit 0
fi

# ── Dry-run: show what would be written ──
if [[ "$DRY_RUN" == "true" ]]; then
    info "Would prepend to ${SSH_CONFIG}:"
    echo ""
    echo "$MANAGED_BLOCK"
    echo ""
    exit 0
fi

# ── Backup existing config ──
if [[ -f "$SSH_CONFIG" ]]; then
    BACKUP="${SSH_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
    info "Backing up ${SSH_CONFIG} → ${BACKUP}"
    cp "$SSH_CONFIG" "$BACKUP"
fi

# ── Prepend managed block ──
info "Writing SSH client config to ${SSH_CONFIG}"
TMP=$(mktemp)
trap 'rm -f "${TMP:-}"' EXIT
printf '%s\n\n' "$MANAGED_BLOCK" > "$TMP"
if [[ -f "$SSH_CONFIG" ]]; then
    cat "$SSH_CONFIG" >> "$TMP"
fi
mv "$TMP" "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

echo
success "SSH client configuration applied"
info "ControlMaster sockets → ${SOCKETS_DIR}"
info "Stop a persisted connection: ssh -O stop <host>"
