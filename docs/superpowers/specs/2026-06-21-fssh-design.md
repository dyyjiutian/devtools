# fssh Design Spec
Date: 2026-06-21

## Overview

A bash script `fssh` that integrates fzf + SSH + tmux for remote development in Ghostty terminal. Reads `~/.ssh/config` for host discovery, presents fzf pickers for host and tmux session selection, and cleans up local terminal mouse state on disconnect.

---

## Directory Structure

```
tools/ssh/
├── fssh          # main script (no extension, directly executable)
└── setup.sh      # SSH client config optimization script
```

`fssh` is designed to be symlinked to `~/bin/fssh` or `/usr/local/bin/fssh`.

---

## `fssh` Script

### Dependencies
- `fzf` — fuzzy picker
- `ssh` — connection

### Flow

1. **Dependency check** — verify `fzf` and `ssh` are in PATH
2. **Parse `~/.ssh/config`** — extract all `Host` entries, skipping `*` wildcards
3. **fzf host picker** — fuzzy search over extracted hosts
4. **List remote tmux sessions** — run a single SSH command:
   ```
   ssh <host> "tmux list-sessions -F '#{session_name}' 2>/dev/null || echo ''"
   ```
5. **fzf session picker** — show existing sessions + `[新建会话]` at bottom
   - If `[新建会话]` selected: prompt for name, default `main`
6. **Register trap** — on EXIT/INT/TERM, run `reset_terminal()`
7. **Connect** — `ssh -t <host> "tmux new-session -As <session_name>"`

### Terminal Cleanup (`reset_terminal`)

When remote tmux has `set -g mouse on`, it sends `\033[?1000h` and related sequences to enable mouse reporting in the local terminal. On abnormal SSH disconnect these are never cancelled, causing Ghostty to misinterpret mouse events as escape sequences.

```bash
reset_terminal() {
    printf '\033[?1000l'   # disable mouse click reporting
    printf '\033[?1002l'   # disable mouse drag reporting
    printf '\033[?1006l'   # disable SGR mouse extension
    stty sane              # reset terminal I/O flags
    tput rmcup 2>/dev/null # exit alternate screen if active
}
trap reset_terminal EXIT INT TERM
```

### Flags
- `--help` — usage information
- `--dry-run` — print what would happen, no SSH connection

---

## `setup.sh` — SSH Client Configuration

Writes a managed config block to `~/.ssh/config` and creates the ControlMaster socket directory.

### Config block inserted at top of `~/.ssh/config`

```
# === fssh managed: SSH client optimization ===
Host *
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%r@%h:%p
    ControlPersist 10m

    ServerAliveInterval 15
    ServerAliveCountMax 3

    ConnectTimeout 10
# === fssh managed end ===
```

### Behavior
- **Idempotent** — skips if managed block already exists
- **Backup** — copies `~/.ssh/config` to `~/.ssh/config.bak.YYYYMMDDHHMMSS` before modifying
- **Creates** `~/.ssh/sockets/` with permissions 700
- **`--dry-run`** — prints what would be written, no file changes
- **`--help`** — usage information

### Rationale for values
- `ControlPersist 10m` — keeps multiplexed connection alive 10 minutes after last session ends, making rapid reconnects instant
- `ServerAliveInterval 15` + `ServerAliveCountMax 3` — detects dead connections within ~45 seconds
- `ConnectTimeout 10` — fails fast on unreachable hosts

---

## Non-goals
- Auto-reconnect on disconnect (user handles reconnect manually)
- Password-based SSH auth (use key-based auth; existing `iterm2/scripts/login.exp` covers passwords)
- Parsing complex `~/.ssh/config` directives (`Include`, `Match`) — only `Host` entries
