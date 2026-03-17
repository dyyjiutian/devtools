#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  --backup    Copy Cursor config from the current environment to <dir>
  --restore   Copy config from <dir> into the current environment

Options:
  --dir <path>   Config directory to read from / write to
                 (default: $(realpath "$SCRIPT_DIR/../config" 2>/dev/null || echo "<script>/../config"))

Examples:
  $(basename "$0") --backup
  $(basename "$0") --restore
  $(basename "$0") --backup  --dir ~/dotfiles/cursor
  $(basename "$0") --restore --dir ~/dotfiles/cursor
EOF
    exit 1
}

# ── Detect Cursor system config path ─────────────────────────────────────────
detect_cursor_config_dir() {
    case "$(uname -s)" in
        Darwin)      echo "$HOME/Library/Application Support/Cursor/User" ;;
        Linux)       echo "$HOME/.config/Cursor/User" ;;
        CYGWIN*|MINGW*|MSYS*) echo "$APPDATA/Cursor/User" ;;
        *)
            echo "Unsupported OS: $(uname -s)" >&2
            exit 1
            ;;
    esac
}

# ── Parse arguments ───────────────────────────────────────────────────────────
COMMAND=""
CONFIG_DIR="$SCRIPT_DIR/../config"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --backup)   COMMAND="backup";  shift ;;
        --restore)  COMMAND="restore"; shift ;;
        --dir)
            [[ -z "${2:-}" ]] && { echo "Error: --dir requires a path"; usage; }
            CONFIG_DIR="$2"; shift 2
            ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

[[ -z "$COMMAND" ]] && usage

CONFIG_DIR="$(realpath "$CONFIG_DIR" 2>/dev/null || echo "$CONFIG_DIR")"
CURSOR_CONFIG="$(detect_cursor_config_dir)"

# ── Backup ────────────────────────────────────────────────────────────────────
do_backup() {
    echo "OS      : $(uname -s)"
    echo "Source  : $CURSOR_CONFIG"
    echo "Dest    : $CONFIG_DIR"
    echo ""

    mkdir -p "$CONFIG_DIR"

    if [[ -f "$CURSOR_CONFIG/settings.json" ]]; then
        cp "$CURSOR_CONFIG/settings.json" "$CONFIG_DIR/settings.json"
        echo "[✓] settings.json"
    else
        echo "[!] settings.json not found, skipped"
    fi

    if [[ -f "$CURSOR_CONFIG/keybindings.json" ]]; then
        cp "$CURSOR_CONFIG/keybindings.json" "$CONFIG_DIR/keybindings.json"
        echo "[✓] keybindings.json"
    else
        echo "[!] keybindings.json not found, skipped"
    fi

    if command -v cursor &>/dev/null; then
        cursor --list-extensions > "$CONFIG_DIR/extensions.txt"
        count="$(grep -c . "$CONFIG_DIR/extensions.txt" || echo 0)"
        echo "[✓] extensions.txt ($count extensions)"
    else
        echo "[!] 'cursor' CLI not found — skipping extensions backup"
        echo "    Run 'Shell Command: Install cursor command in PATH' in Cursor first."
    fi

    echo ""
    echo "Backup complete → $CONFIG_DIR"
}

# ── Restore ───────────────────────────────────────────────────────────────────
do_restore() {
    echo "OS      : $(uname -s)"
    echo "Source  : $CONFIG_DIR"
    echo "Dest    : $CURSOR_CONFIG"
    echo ""

    read -r -p "This will overwrite existing Cursor config files. Continue? [y/N] " answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    echo ""

    mkdir -p "$CURSOR_CONFIG"

    if [[ -f "$CONFIG_DIR/settings.json" ]]; then
        cp "$CONFIG_DIR/settings.json" "$CURSOR_CONFIG/settings.json"
        echo "[✓] settings.json"
    else
        echo "[!] settings.json not found in $CONFIG_DIR, skipped"
    fi

    if [[ -f "$CONFIG_DIR/keybindings.json" ]]; then
        cp "$CONFIG_DIR/keybindings.json" "$CURSOR_CONFIG/keybindings.json"
        echo "[✓] keybindings.json"
    else
        echo "[!] keybindings.json not found in $CONFIG_DIR, skipped"
    fi

    if [[ -f "$CONFIG_DIR/extensions.txt" ]]; then
        if command -v cursor &>/dev/null; then
            echo "Installing extensions..."
            total=0; failed=0
            while IFS= read -r ext || [[ -n "$ext" ]]; do
                [[ -z "$ext" ]] && continue
                if cursor --install-extension "$ext" &>/dev/null; then
                    echo "  [✓] $ext"
                else
                    echo "  [!] failed: $ext"
                    ((failed++)) || true
                fi
                ((total++)) || true
            done < "$CONFIG_DIR/extensions.txt"
            echo "[✓] extensions: $((total - failed))/$total installed"
        else
            echo "[!] 'cursor' CLI not found — skipping extensions install"
            echo "    Run 'Shell Command: Install cursor command in PATH' in Cursor first."
        fi
    else
        echo "[!] extensions.txt not found in $CONFIG_DIR, skipped"
    fi

    echo ""
    echo "Restore complete. Reload Cursor window (⌘⇧P → 'Reload Window') to apply all settings."
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "$COMMAND" in
    backup)  do_backup  ;;
    restore) do_restore ;;
esac
