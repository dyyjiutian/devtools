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
# clicks as escape sequences. The exit trap restores terminal state only after
# an interactive SSH/tmux session has started.
CTRL_SOCK=""   # path to ControlMaster socket, set after host is picked
INTERACTIVE_SESSION_STARTED=false

close_master() {
    # Leave the socket alive — ControlPersist=12h expires it automatically.
    # Clearing the variable prevents reset_terminal from attempting a close.
    CTRL_SOCK=""
}

reset_terminal() {
    [[ "$INTERACTIVE_SESSION_STARTED" == "true" ]] || return

    printf '\033[?1000l'   # disable X10 mouse click reporting
    printf '\033[?1002l'   # disable mouse drag (button-event) reporting
    printf '\033[?1006l'   # disable SGR extended mouse mode
    printf '\033[?2004l'   # disable bracketed paste
    printf '\033[>4;0m'    # disable xterm modifyOtherKeys
    printf '\033[<u'       # pop kitty keyboard protocol flags
    printf '\033[?25h'     # ensure cursor is visible
    stty sane 2>/dev/null || true
    tput rmcup 2>/dev/null || true  # leave alternate screen; restore scrollback
    close_master
}
trap reset_terminal EXIT INT TERM

# ── Help ─────────────────────────────────────────────────────────────────────
show_help() {
    cat <<'EOF'
fssh — fuzzy SSH + tmux session picker for Ghostty

Usage:
  fssh                  Interactive: pick SSH host, then tmux session
  fssh <query>          Resolve Host alias: exact match, else substring;
                        unique hit connects, multiple hits open fzf
  fssh -n               Skip tmux — plain SSH login after host pick
  fssh <query> -n       Resolve <query>, then plain SSH
  fssh -l               List all hosts from SSH config (incl. Include) and exit
  fssh -h               Show this help

Flags (long forms also accepted):
  -h, --help            Show this help
  -l, --list            List available SSH hosts and exit
  -n, --no-tmux         Plain SSH — skip tmux session picker entirely

Host query matching (Host aliases only; wildcards excluded):
  1. Case-insensitive exact match against Host aliases
  2. Else case-insensitive substring match
  3. 1 hit → use it; multiple → fzf on matches; 0 → error

Interactive tmux flow:
  1. Reads ~/.ssh/config Host entries, following Include (wildcards excluded)
  2. Resolve query or fzf picker → select host
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
# Track visited config paths (newline-delimited) to avoid Include cycles.
_FSSH_SEEN_CONFIGS=""

# Resolve one Include path pattern to concrete files (OpenSSH user-config rules:
# ~ expands; relative paths are under ~/.ssh; globs expand in lexical order).
_fssh_expand_include_pattern() {
    local pattern="$1"
    local expanded tilde_slash='~/'
    case "$pattern" in
        # Use a variable for the # removal pattern so bash does not tilde-expand ~/
        # inside ${param#~/} (which would leave the leading ~ unstripped).
        "~/"*) expanded="${HOME}/${pattern#"$tilde_slash"}" ;;
        "~")   expanded="${HOME}" ;;
        /*)    expanded="$pattern" ;;
        *)     expanded="${HOME}/.ssh/${pattern}" ;;
    esac

    # compgen -G expands globs; plain paths must exist to be listed.
    if compgen -G "$expanded" >/dev/null 2>&1; then
        compgen -G "$expanded" | LC_ALL=C sort
    fi
}

# Canonical path for cycle detection (best-effort; Bash 3.2 compatible).
_fssh_abs_path() {
    local file="$1"
    local dir base
    if command -v realpath >/dev/null 2>&1; then
        realpath "$file" 2>/dev/null && return 0
    fi
    dir=$(cd "$(dirname "$file")" 2>/dev/null && pwd) || { printf '%s\n' "$file"; return 0; }
    base=$(basename "$file")
    printf '%s/%s\n' "$dir" "$base"
}

# Recursively emit Host alias tokens from a config file and its Include targets.
_fssh_collect_hosts_from_file() {
    local file="$1"
    local abs line
    local -a words
    [[ -f "$file" && -r "$file" ]] || return 0

    abs=$(_fssh_abs_path "$file")
    if printf '%s\n' "$_FSSH_SEEN_CONFIGS" | grep -Fxq -- "$abs"; then
        return 0
    fi
    _FSSH_SEEN_CONFIGS="${_FSSH_SEEN_CONFIGS}${abs}"$'\n'

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        # trim leading whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -n "$line" ]] || continue

        # Split into words (SSH config is whitespace-separated).
        # Bash 3.2: avoid mapfile; use read -a.
        words=()
        # shellcheck disable=SC2086
        read -r -a words <<< "$line"
        [[ ${#words[@]} -ge 2 ]] || continue

        # Match keywords with case patterns — do not fork tr/awk per line
        # (OpenSSH keywords are case-insensitive; per-line tr previously cost seconds).
        case "${words[0]}" in
            [Ii][Nn][Cc][Ll][Uu][Dd][Ee])
                local i inc
                for ((i = 1; i < ${#words[@]}; i++)); do
                    while IFS= read -r inc || [[ -n "$inc" ]]; do
                        [[ -n "$inc" ]] || continue
                        _fssh_collect_hosts_from_file "$inc"
                    done < <(_fssh_expand_include_pattern "${words[i]}")
                done
                ;;
            [Hh][Oo][Ss][Tt])
                local i
                for ((i = 1; i < ${#words[@]}; i++)); do
                    printf '%s\n' "${words[i]}"
                done
                ;;
        esac
    done < "$file"
}

list_hosts() {
    local config="${HOME}/.ssh/config"
    [[ -f "$config" ]] || error "~/.ssh/config not found."
    _FSSH_SEEN_CONFIGS=""
    _fssh_collect_hosts_from_file "$config" \
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

# ── Dependency check ──────────────────────────────────────────────────────────
check_deps() {
    local missing=()
    command -v fzf &>/dev/null || missing+=("fzf")
    command -v ssh &>/dev/null || missing+=("ssh")
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}\nInstall: brew install ${missing[*]}"
    fi
}

# ── Host query matching (aliases only) ────────────────────────────────────────
# Exact case-insensitive match wins; otherwise substring. Prints matching aliases.
match_hosts() {
    local query="$1"
    local hosts exact
    hosts=$(list_hosts)
    [[ -n "$hosts" ]] || return 0

    exact=$(printf '%s\n' "$hosts" \
        | awk -v q="$query" 'BEGIN{ql=tolower(q)} tolower($0)==ql')
    if [[ -n "$exact" ]]; then
        printf '%s\n' "$exact"
        return 0
    fi

    printf '%s\n' "$hosts" \
        | awk -v q="$query" 'BEGIN{ql=tolower(q)} ql!="" && index(tolower($0), ql)'
}

# ── fzf host picker ───────────────────────────────────────────────────────────
# Optional $1: pre-filtered host list (newline-separated). Default: all hosts.
pick_host() {
    local hosts="${1:-}"
    if [[ -z "$hosts" ]]; then
        hosts=$(list_hosts)
    fi
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

# Resolve a query to a single Host alias (exact → substring → fzf if multiple).
resolve_host() {
    local query="$1"
    local matches count

    matches=$(match_hosts "$query")
    if [[ -z "$matches" ]]; then
        error "No SSH host matching '${query}' in ~/.ssh/config"
    fi

    count=$(printf '%s\n' "$matches" | grep -c . || true)
    if [[ "$count" -eq 1 ]]; then
        printf '%s\n' "$matches"
        return 0
    fi

    pick_host "$matches"
}

# ── SSH ControlMaster ─────────────────────────────────────────────────────────
# Uses a host-stable socket path so the master is reused across fssh runs.
# ControlPersist=12h keeps it alive 12 h after last use; the next run to the
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
    # ServerAlive* lets ssh proactively detect a dead master (laptop sleep,
    # network switch, VPN drop) and tear it down within ~90 s, so a stale socket
    # doesn't make the next mssh hang on a long TCP timeout.
    ssh -o ControlMaster=yes \
        -o ControlPath="$CTRL_SOCK" \
        -o ControlPersist=12h \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -fN "$host" || error "Failed to connect to ${host}"
}

# Wrapper: route any ssh call through the open master socket
mssh() { ssh -o ControlMaster=no -o ControlPath="$CTRL_SOCK" "$@"; }

# Run tmux through a login shell so remote user startup files can add
# ~/.local/bin (or another user-local directory) to PATH. Each argument is
# quoted for the remote shell before being passed to `bash -lc`.
remote_tmux() {
    local ssh_args=()
    if [[ "${1:-}" == "-t" ]]; then
        ssh_args+=("-t")
        shift
    fi

    local host="$1"
    shift

    local tmux_command="tmux"
    local arg quoted_command
    for arg in "$@"; do
        tmux_command+=" $(printf '%q' "$arg")"
    done

    quoted_command=$(printf '%q' "$tmux_command")
    # Bash 3.2 (the macOS system Bash) raises "unbound variable" for an empty
    # "${array[@]}" under set -u. The + expansion emits no argument when empty.
    mssh ${ssh_args[@]+"${ssh_args[@]}"} "$host" "bash -lc $quoted_command"
}

# ── Remote tmux session lister ────────────────────────────────────────────────
list_remote_sessions() {
    local host="$1"
    local sessions failure_detail

    if ! sessions=$(remote_tmux "$host" list-sessions -F '#{session_name}' 2>&1); then
        failure_detail=$(printf '%s' "$sessions" | tr '\r\n' '  ')
        if [[ -n "$failure_detail" ]]; then
            warn "无法列出 ${host} 上的远端 tmux session：${failure_detail}"
        else
            warn "无法列出 ${host} 上的远端 tmux session"
        fi
        return 0
    fi

    printf '%s\n' "$sessions" | grep -v '^$' || true
}

# ── fzf session picker ────────────────────────────────────────────────────────
NEW_SESSION_LABEL="[new session]"
DIRECT_LOGIN_LABEL="[ssh login]"

# Build session-picker lines: [ssh login], existing sessions, [new session].
session_menu_entries() {
    local sessions="${1:-}"
    if [[ -n "$sessions" ]]; then
        printf '%s\n%s\n%s\n' "$DIRECT_LOGIN_LABEL" "$sessions" "$NEW_SESSION_LABEL"
    else
        printf '%s\n%s\n' "$DIRECT_LOGIN_LABEL" "$NEW_SESSION_LABEL"
    fi
}

# Returns either a session name, NEW_SESSION_LABEL, or DIRECT_LOGIN_LABEL
pick_session() {
    local host="$1"
    local sessions entries
    sessions=$(list_remote_sessions "$host")
    entries=$(session_menu_entries "$sessions")

    printf '%s\n' "$entries" \
        | fzf --prompt="Tmux Session ❯ " --height=40% --reverse --border --no-multi
}

# ── Plain SSH mode (--no-tmux or [直接登录] chosen) ───────────────────────────
connect_plain() {
    success "→ ${HOST}  (plain SSH)"
    INTERACTIVE_SESSION_STARTED=true
    mssh "$HOST"
}

# ── Main ──────────────────────────────────────────────────────────────────────
fssh_main() {
    local NO_TMUX=false
    local DIRECT_HOST=""
    local CHOICE SESSION _tmux_check rc

    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)     show_help ;;
            --list|-l)     list_hosts_detail; exit 0 ;;
            --no-tmux|-n)  NO_TMUX=true; shift ;;
            -*)            error "Unknown option: $1. Run fssh -h for usage." ;;
            *)             DIRECT_HOST="$1"; shift ;;
        esac
    done

    check_deps

    # HOST is global: connect_plain reads it from the caller scope.
    if [[ -n "$DIRECT_HOST" ]]; then
        HOST=$(resolve_host "$DIRECT_HOST")
    else
        HOST=$(pick_host)
    fi
    if [[ -z "$HOST" ]]; then
        warn "No host selected."
        exit 0
    fi

    establish_master "$HOST"

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

    success "→ ${HOST}  session: ${SESSION}"

    # Probe without PTY so the shell's raw stderr (e.g. "tmux: command not found")
    # comes back through the non-PTY SSH channel and can be captured and displayed.
    if ! _tmux_check=$(remote_tmux "$HOST" -V 2>&1); then
        [[ -n "$_tmux_check" ]] && echo "$_tmux_check" >&2
        error "tmux not available on ${HOST}"
    fi

    # Do not use exec — trap must fire on exit to clean up terminal state
    INTERACTIVE_SESSION_STARTED=true
    remote_tmux -t "$HOST" new-session -As "$SESSION" || {
        rc=$?
        echo -e "\033[31m[ERROR]\033[0m Remote tmux exited ${rc} on ${HOST}" >&2
        exit $rc
    }
}

if [[ "${FSSH_NO_MAIN:-}" != "1" ]]; then
    fssh_main "$@"
fi
