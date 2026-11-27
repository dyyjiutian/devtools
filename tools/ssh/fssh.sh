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
    [[ "$INTERACTIVE_SESSION_STARTED" == "true" ]] || return 0

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
  fssh <query> -n       Resolve <query>, then plain SSH (no tmux)
  fssh <query> -t <session>
                        Resolve <query>, then attach tmux session
                        (host query required with -t)
  fssh -l               List all hosts from SSH config (incl. Include) and exit
  fssh -a user@host[:port]  Install a public key and add an SSH Host
  fssh -a user@host --dry-run  Preview without local or remote changes
  fssh -h               Show this help

Flags (long forms also accepted):
  -h, --help            Show this help
  -l, --list            List available SSH hosts and exit
  -a, --add TARGET      Add user@hostname or user@ip, optionally with :port
  --dry-run             Preview --add only
  -n, --no-tmux         Plain SSH — skip tmux session picker entirely
  -t, --tmux SESSION    Attach tmux session (requires host query; mutually
                        exclusive with -n/--no-tmux)

Host / session query matching (Host aliases or session names):
  1. Case-insensitive exact match
  2. Else case-insensitive substring match
  3. 1 hit → use it; multiple → fzf on matches; 0 → error

Interactive tmux flow (no -n / -t):
  1. Reads ~/.ssh/config Host entries, following Include (wildcards excluded)
  2. Resolve query or fzf picker → select host
  3. SSH to host, list tmux sessions
  4. fzf picker → select existing session, "[new session]" to create one,
     or "[ssh login]" to drop into a plain shell (no tmux)
  5. Connects accordingly

On any exit (normal or network disconnect), local terminal mouse state is
reset automatically so Ghostty mouse events work correctly again.

Requirements: fzf, ssh; --add also requires ssh-copy-id and ssh-keygen
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

_fssh_split_config_line() {
    local line="$1" char token="" quoted=false escaped=false active=false i
    _FSSH_WORDS=()
    if [[ "$line" =~ ^([^[:space:]=]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
        line="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    fi
    for ((i = 0; i < ${#line}; i++)); do
        char="${line:i:1}"
        if [[ "$escaped" == "true" ]]; then
            token="${token}${char}"; escaped=false; active=true
        elif [[ "$char" == '\' ]]; then
            escaped=true; active=true
        elif [[ "$char" == '"' ]]; then
            if [[ "$quoted" == "true" ]]; then quoted=false; else quoted=true; fi
            active=true
        elif [[ "$quoted" == "false" && "$char" == "#" ]]; then
            break
        elif [[ "$quoted" == "false" && "$char" == [[:space:]] ]]; then
            if [[ "$active" == "true" ]]; then
                _FSSH_WORDS+=("$token"); token=""; active=false
            fi
        else
            token="${token}${char}"; active=true
        fi
    done
    [[ "$quoted" == "false" && "$escaped" == "false" ]] \
        || error "Invalid SSH config quoting."
    [[ "$active" == "false" ]] || _FSSH_WORDS+=("$token")
}

# Recursively emit Host alias tokens from a config file and its Include targets.
_fssh_collect_hosts_from_file() {
    local file="$1"
    local abs line
    local -a words
    [[ -f "$file" ]] || return 0
    [[ -r "$file" ]] || error "Cannot read SSH config: ${file}"

    abs=$(_fssh_abs_path "$file")
    if printf '%s\n' "$_FSSH_SEEN_CONFIGS" | grep -Fxq -- "$abs"; then
        return 0
    fi
    _FSSH_SEEN_CONFIGS="${_FSSH_SEEN_CONFIGS}${abs}"$'\n'

    while IFS= read -r line || [[ -n "$line" ]]; do
        # trim leading whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -n "$line" ]] || continue
        case "$line" in
            [Hh][Oo][Ss][Tt][=[:space:]]*|[Ii][Nn][Cc][Ll][Uu][Dd][Ee][=[:space:]]*) ;;
            *) continue ;;
        esac

        _fssh_split_config_line "$line"
        words=("${_FSSH_WORDS[@]+"${_FSSH_WORDS[@]}"}")
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
        | awk '!/[*?]/' \
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

# Add a direct connection using a dedicated alias and the default Ed25519 key.
add_host() (
    local target="$1" dry_run="$2"
    local user host port=22 alias config="${HOME}/.ssh/config"
    local key="${HOME}/.ssh/id_ed25519" tmp="" backup="" existing
    trap '[[ -z "$tmp" ]] || rm -f "$tmp"' EXIT

    [[ "$target" == *@* && "${target#*@}" != *"@"* ]] \
        || error "Expected user@hostname or user@hostname:port."
    user="${target%%@*}"
    host="${target#*@}"
    if [[ "$host" == *:* ]]; then
        port="${host##*:}"
        host="${host%:*}"
        [[ "$port" =~ ^[0-9]{1,5}$ ]] || error "Invalid SSH port."
        port=$((10#$port))
        [[ "$port" -ge 1 && "$port" -le 65535 ]] || error "Invalid SSH port."
    fi
    [[ "$user" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*[$]?$ ]] || error "Invalid SSH user."
    [[ "$host" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]] || error "Invalid SSH hostname or IPv4 address."
    alias="${user}-${host}"
    [[ "$port" == 22 ]] || alias="${alias}-${port}"

    [[ ! -L "$config" ]] || error "Refusing to replace symlinked SSH config: ${config}"
    if [[ -f "$config" ]]; then
        existing=$(list_hosts) || error "Cannot inspect existing SSH hosts; no changes made."
        if printf '%s\n' "$existing" | awk -v a="$alias" 'tolower($0)==tolower(a) {found=1} END {exit !found}'; then
            error "SSH Host '${alias}' already exists; no changes made."
        fi
    fi
    info "Target: ${user}@${host}:${port}; SSH Host alias: ${alias}"
    if [[ "$dry_run" == "true" ]]; then
        info "Would install ${key}.pub on the remote account and update ${config}."
        return 0
    fi
    command -v ssh >/dev/null 2>&1 || error "Missing required tool: ssh"
    command -v ssh-copy-id >/dev/null 2>&1 || error "Missing required tool: ssh-copy-id"
    command -v ssh-keygen >/dev/null 2>&1 || error "Missing required tool: ssh-keygen"
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    if [[ ! -e "$key" && ! -e "${key}.pub" ]]; then
        info "Generating an unencrypted Ed25519 key at ${key}."
        ssh-keygen -t ed25519 -N '' -f "$key" || error "SSH key generation failed."
    fi
    [[ -f "$key" && -f "${key}.pub" ]] || error "Both ${key} and ${key}.pub are required."

    info "Installing the public key on ${user}@${host}; verify the host key and enter the remote password if prompted."
    ssh-copy-id -F /dev/null -i "${key}.pub" -p "$port" \
        -o ControlMaster=no -o ControlPath=none "${user}@${host}" \
        || error "Public key installation failed; local SSH config was not changed."
    ssh -F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes \
        -o ControlMaster=no -o ControlPath=none -i "$key" -p "$port" \
        "${user}@${host}" true \
        || error "Key authentication failed; local SSH config was not changed."

    tmp=$(mktemp "${HOME}/.ssh/.fssh-config.XXXXXX") || error "Cannot create temporary SSH config."
    {
        printf 'Host %s\n    HostName %s\n    User %s\n    Port %s\n    IdentityFile ~/.ssh/id_ed25519\n    ProxyCommand none\n    ProxyJump none\n\nHost *\n' \
            "$alias" "$host" "$user" "$port"
        [[ ! -f "$config" ]] || cat "$config"
    } >"$tmp" || error "Cannot write temporary SSH config."
    chmod 600 "$tmp" || error "Cannot secure temporary SSH config."
    if [[ -f "$config" ]]; then
        backup=$(mktemp "${config}.bak.XXXXXX") || error "Cannot create SSH config backup."
        cp -p "$config" "$backup" || error "Cannot back up SSH config."
        info "Backup: ${backup}"
    fi
    mv -f "$tmp" "$config" || error "Cannot update SSH config."
    tmp=""
    success "Added SSH Host ${alias}. Connect with: fssh ${alias}"
)

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
# ~/.local/bin (or another user-local directory) to PATH. Also prepend
# common prefixes that login bash often misses — Apple Silicon Homebrew
# is typically added from ~/.zprofile, which bash -lc does not read.
# $PATH and $HOME must expand on the remote host, not locally.
remote_tmux() {
    local ssh_args=()
    if [[ "${1:-}" == "-t" ]]; then
        ssh_args+=("-t")
        shift
    fi

    local host="$1"
    shift

    local tmux_command="tmux"
    local arg quoted_command remote_script
    for arg in "$@"; do
        tmux_command+=" $(printf '%q' "$arg")"
    done

    remote_script="PATH=\"\$PATH:/opt/homebrew/bin:/usr/local/bin:\$HOME/.local/bin\"; ${tmux_command}"
    quoted_command=$(printf '%q' "$remote_script")
    # Bash 3.2 (the macOS system Bash) raises "unbound variable" for an empty
    # "${array[@]}" under set -u. The + expansion emits no argument when empty.
    mssh ${ssh_args[@]+"${ssh_args[@]}"} "$host" "bash -lc $quoted_command"
}

# ── Remote tmux session lister ────────────────────────────────────────────────
list_remote_sessions() {
    local host="$1"
    local sessions failure_detail stderr_file rc=0

    # Keep stdout (session names) separate from stderr (login-shell noise such as
    # nvm/npmrc warnings from bash -lc). Merging with 2>&1 polluted the fzf menu.
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/fssh-tmux-stderr.XXXXXX") || {
        warn "无法创建临时文件以捕获远端 stderr"
        return 0
    }

    sessions=$(remote_tmux "$host" list-sessions -F '#{session_name}' 2>"$stderr_file") || rc=$?

    if [[ "$rc" -ne 0 ]]; then
        failure_detail=$(tr '\r\n' '  ' <"$stderr_file")
        rm -f "$stderr_file"
        if [[ -n "$failure_detail" ]]; then
            warn "无法列出 ${host} 上的远端 tmux session：${failure_detail}"
        else
            warn "无法列出 ${host} 上的远端 tmux session"
        fi
        return 0
    fi

    rm -f "$stderr_file"
    printf '%s\n' "$sessions" | grep -v '^$' || true
}

# ── fzf session picker ────────────────────────────────────────────────────────
NEW_SESSION_LABEL="[new session]"
DIRECT_LOGIN_LABEL="[ssh login]"

# Exact case-insensitive match wins; otherwise substring. $1=query $2=sessions list.
match_sessions() {
    local query="$1"
    local sessions="${2:-}"
    local exact
    [[ -n "$sessions" ]] || return 0

    exact=$(printf '%s\n' "$sessions" \
        | awk -v q="$query" 'BEGIN{ql=tolower(q)} tolower($0)==ql')
    if [[ -n "$exact" ]]; then
        printf '%s\n' "$exact"
        return 0
    fi

    printf '%s\n' "$sessions" \
        | awk -v q="$query" 'BEGIN{ql=tolower(q)} ql!="" && index(tolower($0), ql)'
}

# Optional $1: pre-filtered session list (newline-separated).
pick_session_name() {
    local sessions="${1:-}"
    [[ -n "$sessions" ]] || error "No tmux sessions to pick from."

    local selected
    selected=$(printf '%s\n' "$sessions" \
        | fzf --prompt="Tmux Session ❯ " --height=40% --reverse --border --no-multi)

    printf '%s\n' "$selected"
}

# Resolve a query to a single session name (exact → substring → fzf if multiple).
# $1=query $2=newline-separated session list from the remote host.
resolve_session() {
    local query="$1"
    local sessions="${2:-}"
    local matches count

    matches=$(match_sessions "$query" "$sessions")
    if [[ -z "$matches" ]]; then
        error "No tmux session matching '${query}'"
    fi

    count=$(printf '%s\n' "$matches" | grep -c . || true)
    if [[ "$count" -eq 1 ]]; then
        printf '%s\n' "$matches"
        return 0
    fi

    pick_session_name "$matches"
}

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

# Attach (or create-and-attach) a named tmux session on HOST.
connect_tmux_session() {
    local session="$1"
    local _tmux_check rc

    success "→ ${HOST}  session: ${session}"

    # Probe without PTY so the shell's raw stderr (e.g. "tmux: command not found")
    # comes back through the non-PTY SSH channel and can be captured and displayed.
    if ! _tmux_check=$(remote_tmux "$HOST" -V 2>&1); then
        [[ -n "$_tmux_check" ]] && echo "$_tmux_check" >&2
        error "tmux not available on ${HOST}"
    fi

    # Do not use exec — trap must fire on exit to clean up terminal state
    INTERACTIVE_SESSION_STARTED=true
    remote_tmux -t "$HOST" new-session -As "$session" || {
        rc=$?
        echo -e "\033[31m[ERROR]\033[0m Remote tmux exited ${rc} on ${HOST}" >&2
        exit $rc
    }
}

# ── Main ──────────────────────────────────────────────────────────────────────
fssh_main() {
    local NO_TMUX=false
    local DIRECT_HOST=""
    local SESSION_QUERY=""
    local ADD_TARGET="" DRY_RUN=false LIST=false
    local CHOICE SESSION sessions

    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)     show_help ;;
            --list|-l)     LIST=true; shift ;;
            --dry-run)     DRY_RUN=true; shift ;;
            --add|-a)
                [[ -n "${2:-}" && "${2:0:1}" != "-" ]] \
                    || error "-a/--add requires a target."
                [[ -z "$ADD_TARGET" ]] || error "-a/--add may only be specified once."
                ADD_TARGET="$2"
                shift 2
                ;;
            --no-tmux|-n)  NO_TMUX=true; shift ;;
            --tmux|-t)
                [[ -n "${2:-}" && "${2:0:1}" != "-" ]] \
                    || error "-t/--tmux requires a session name. Run fssh -h for usage."
                SESSION_QUERY="$2"
                shift 2
                ;;
            -*)            error "Unknown option: $1. Run fssh -h for usage." ;;
            *)
                if [[ -n "$DIRECT_HOST" ]]; then
                    error "Unexpected argument: $1. Run fssh -h for usage."
                fi
                DIRECT_HOST="$1"
                shift
                ;;
        esac
    done

    if [[ -n "$ADD_TARGET" ]]; then
        [[ -z "$DIRECT_HOST" && -z "$SESSION_QUERY" && "$NO_TMUX" == "false" && "$LIST" == "false" ]] \
            || error "-a/--add cannot be combined with connection or list options."
        add_host "$ADD_TARGET" "$DRY_RUN"
        return
    fi
    [[ "$DRY_RUN" == "false" ]] || error "--dry-run requires -a/--add."
    if [[ "$LIST" == "true" ]]; then
        list_hosts_detail
        return
    fi

    if [[ -n "$SESSION_QUERY" && "$NO_TMUX" == "true" ]]; then
        error "-t/--tmux and -n/--no-tmux are mutually exclusive."
    fi
    if [[ -n "$SESSION_QUERY" && -z "$DIRECT_HOST" ]]; then
        error "-t/--tmux requires a host query."
    fi

    check_deps

    # HOST is global: connect_plain / connect_tmux_session read it from caller scope.
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

    if [[ -n "$SESSION_QUERY" ]]; then
        sessions=$(list_remote_sessions "$HOST")
        SESSION=$(resolve_session "$SESSION_QUERY" "$sessions")
        if [[ -z "$SESSION" ]]; then
            warn "No session selected."
            exit 0
        fi
        connect_tmux_session "$SESSION"
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

    connect_tmux_session "$SESSION"
}

if [[ "${FSSH_NO_MAIN:-}" != "1" ]]; then
    fssh_main "$@"
fi
