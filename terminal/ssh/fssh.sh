#!/usr/bin/env bash
set -euo pipefail

info()    { echo -e "\033[34m[INFO]\033[0m $1" >&2; }
success() { echo -e "\033[32m[OK]\033[0m $1" >&2; }
warn()    { echo -e "\033[33m[WARN]\033[0m $1" >&2; }
error()   { echo -e "\033[31m[ERROR]\033[0m $1" >&2; exit 1; }

# ── Terminal + connection cleanup ─────────────────────────────────────────────
# When remote tmux has `set -g mouse on`, it sends \033[?1000h (and related)
# to enable mouse reporting in the local terminal. On abnormal SSH disconnect
# these sequences are never cancelled, causing Ghostty to misinterpret mouse
# clicks as escape sequences. This trap fires on any exit (normal or signal).
CTRL_SOCK=""   # path to ControlMaster socket, set after host is picked

close_master() {
    # Leave the socket alive — ControlPersist=600 expires it automatically.
    # Clearing the variable prevents reset_terminal from attempting a close.
    CTRL_SOCK=""
}

reset_terminal() {
    printf '\033[?1000l'   # disable X10 mouse click reporting
    printf '\033[?1002l'   # disable mouse drag (button-event) reporting
    printf '\033[?1006l'   # disable SGR extended mouse mode
    stty sane 2>/dev/null || true
    close_master
}
trap reset_terminal EXIT INT TERM

# ── Help ─────────────────────────────────────────────────────────────────────
show_help() {
    cat <<'EOF'
fssh — fuzzy SSH + tmux session picker for Ghostty

Usage:
  fssh                  Interactive: pick SSH host, then tmux session
  fssh <host>           Skip host picker — go straight to tmux session picker
  fssh -n               Skip tmux — plain SSH login after host pick
  fssh <host> -n        Plain SSH directly to <host>
  fssh -l               List all hosts from ~/.ssh/config and exit
  fssh -h               Show this help

Flags (long forms also accepted):
  -h, --help            Show this help
  -l, --list            List available SSH hosts and exit
  -n, --no-tmux         Plain SSH — skip tmux session picker entirely

Interactive tmux flow:
  1. Reads ~/.ssh/config for Host entries (wildcards excluded)
  2. fzf picker → select host
  3. SSH to host, list tmux sessions
  4. fzf picker → select existing session, "[新建会话]" to create one,
     or "[直接登录]" to drop into a plain shell (no tmux)
  5. Connects accordingly

On any exit (normal or network disconnect), local terminal mouse state is
reset automatically so Ghostty mouse events work correctly again.

Requirements: fzf, ssh
EOF
    exit 0
}

# ── List hosts ────────────────────────────────────────────────────────────────
list_hosts() {
    local config="${HOME}/.ssh/config"
    [[ -f "$config" ]] || error "~/.ssh/config not found."
    grep -E '^[[:space:]]*Host[[:space:]]' "$config" \
        | awk '{for(i=2;i<=NF;i++) print $i}' \
        | grep -v '[*?]' \
        | sort -u
}

# Uses `ssh -G` to resolve the effective config (handles Include, Match, defaults)
list_hosts_detail() {
    local hosts; hosts=$(list_hosts)
    {
        printf 'NAME\tHOSTNAME / IP\tUSER\tPORT\n'
        printf '%s\n' "$hosts" | xargs -P 8 -I{} bash -c '
            info=$(ssh -G "$1" 2>/dev/null)
            h=$(awk "/^hostname /{print \$2; exit}" <<< "$info")
            u=$(awk "/^user /{print \$2; exit}" <<< "$info")
            p=$(awk "/^port /{print \$2; exit}" <<< "$info")
            printf "%s\t%s\t%s\t%s\n" "$1" "${h:--}" "${u:--}" "${p:-22}"
        ' _ {} | sort
    } | column -t -s $'\t'
}

# ── Flags ─────────────────────────────────────────────────────────────────────
NO_TMUX=false

DIRECT_HOST=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)     show_help ;;
        --list|-l)     list_hosts_detail; exit 0 ;;
        --no-tmux|-n)  NO_TMUX=true; shift ;;
        -*)            error "Unknown option: $1. Run fssh -h for usage." ;;
        *)             DIRECT_HOST="$1"; shift ;;
    esac
done

# ── Dependency check ──────────────────────────────────────────────────────────
check_deps() {
    local missing=()
    command -v fzf &>/dev/null || missing+=("fzf")
    command -v ssh &>/dev/null || missing+=("ssh")
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}\nInstall: brew install ${missing[*]}"
    fi
}

# ── fzf host picker ───────────────────────────────────────────────────────────
pick_host() {
    local hosts
    hosts=$(list_hosts)
    [[ -n "$hosts" ]] || error "No hosts found in ~/.ssh/config (only wildcard entries exist)."

    local selected
    selected=$(printf '%s\n' "$hosts" \
        | fzf --prompt="SSH Host ❯ " --height=60% --reverse --border --no-multi \
              --preview "ssh -G {} 2>/dev/null \
                  | awk '/^(hostname|user|port|proxyjump|proxycommand) /{print} /^identityfile /{if(!seen++){print}}' \
                  | sed '/ none\$/d' \
                  | column -t || echo '(no info)'" \
              --preview-window 'right:45%:wrap')

    printf '%s\n' "$selected"
}

# ── SSH ControlMaster ─────────────────────────────────────────────────────────
# Uses a host-stable socket path so the master is reused across fssh runs.
# ControlPersist=600 keeps it alive 10 min after last use; the next run to the
# same host within that window skips the handshake entirely.
establish_master() {
    local host="$1"
    local safe_host="${host//[^a-zA-Z0-9._-]/_}"
    CTRL_SOCK="${TMPDIR:-/tmp}/fssh-${safe_host}.ctl"

    # Reuse existing master if it is still alive
    if ssh -O check -o ControlPath="$CTRL_SOCK" "$host" &>/dev/null; then
        return 0
    fi

    info "Connecting to ${host}…"
    ssh -o ControlMaster=yes \
        -o ControlPath="$CTRL_SOCK" \
        -o ControlPersist=600 \
        -fN "$host" || error "Failed to connect to ${host}"
}

# Wrapper: route any ssh call through the open master socket
mssh() { ssh -o ControlMaster=no -o ControlPath="$CTRL_SOCK" "$@"; }

# ── Remote tmux session lister ────────────────────────────────────────────────
list_remote_sessions() {
    local host="$1"
    mssh "$host" "tmux list-sessions -F '#{session_name}' 2>/dev/null" 2>/dev/null \
        | grep -v '^$' || true
}

# ── fzf session picker ────────────────────────────────────────────────────────
NEW_SESSION_LABEL="[new session]"
DIRECT_LOGIN_LABEL="[ssh login]"

# Returns either a session name, NEW_SESSION_LABEL, or DIRECT_LOGIN_LABEL
pick_session() {
    local host="$1"
    local sessions
    sessions=$(list_remote_sessions "$host")

    local entries
    if [[ -n "$sessions" ]]; then
        entries=$(printf '%s\n%s\n%s\n'  "$DIRECT_LOGIN_LABEL" "$NEW_SESSION_LABEL" "$sessions" )
    else
        entries=$(printf '%s\n%s\n' "$NEW_SESSION_LABEL" "$DIRECT_LOGIN_LABEL")
    fi

    printf '%s\n' "$entries" \
        | fzf --prompt="Tmux Session ❯ " --height=40% --reverse --border --no-multi
}

# ── Main ──────────────────────────────────────────────────────────────────────
check_deps

if [[ -n "$DIRECT_HOST" ]]; then
    HOST="$DIRECT_HOST"
else
    HOST=$(pick_host)
fi
if [[ -z "$HOST" ]]; then
    warn "No host selected."
    exit 0
fi

establish_master "$HOST"

# ── Plain SSH mode (--no-tmux or [直接登录] chosen) ───────────────────────────
connect_plain() {
    success "→ ${HOST}  (plain SSH)"
    mssh "$HOST"
}

if [[ "$NO_TMUX" == "true" ]]; then
    connect_plain
    exit 0
fi

CHOICE=$(pick_session "$HOST")

case "$CHOICE" in
    "")
        warn "No session selected."
        exit 0
        ;;
    "$DIRECT_LOGIN_LABEL")
        connect_plain
        exit 0
        ;;
    "$NEW_SESSION_LABEL")
        printf 'Session name [main]: ' >&2
        read -r SESSION
        SESSION="${SESSION:-main}"
        ;;
    *)
        SESSION="$CHOICE"
        ;;
esac

SESSION_Q=$(printf '%q' "$SESSION")

success "→ ${HOST}  session: ${SESSION}"

# Probe without PTY so the shell's raw stderr (e.g. "tmux: command not found")
# comes back through the non-PTY SSH channel and can be captured and displayed.
if ! _tmux_check=$(mssh "$HOST" "tmux -V" 2>&1); then
    [[ -n "$_tmux_check" ]] && echo "$_tmux_check" >&2
    error "tmux not available on ${HOST}"
fi

# Do not use exec — trap must fire on exit to clean up terminal state
mssh -t "$HOST" "tmux new-session -As $SESSION_Q" || {
    rc=$?
    echo -e "\033[31m[ERROR]\033[0m Remote tmux exited ${rc} on ${HOST}" >&2
    exit $rc
}
