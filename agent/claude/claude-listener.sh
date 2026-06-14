#!/usr/bin/env bash
# claude-listener.sh — Mac 端通知监听器
#
# 监听本地端口，收到远程 Claude SessionEnd 通知后播放系统提示音。
# 通常由 mac_ssh_hook.sh 或 launchd 启动，勿直接手动运行（除非调试）。

set -euo pipefail

PORT="${CLAUDE_LISTENER_PORT:-19999}"
BIND_HOST="${CLAUDE_LISTENER_HOST:-127.0.0.1}"
SOUND="${CLAUDE_LISTENER_SOUND:-/System/Library/Sounds/Funk.aiff}"
PID_FILE="${CLAUDE_LISTENER_PID_FILE:-/tmp/claude-listener.pid}"
LOG_FILE="${CLAUDE_LISTENER_LOG_FILE:-/tmp/claude-listener.log}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_FILE"
}

play_sound() {
  if [[ -f "$SOUND" ]]; then
    /usr/bin/afplay "$SOUND" &
    log "played sound: $SOUND"
  else
    log "sound file not found: $SOUND"
  fi
}

cleanup() {
  rm -f "$PID_FILE"
  log "listener stopped"
  exit 0
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || {
    echo "claude-listener.sh requires macOS" >&2
    exit 1
  }
}

require_macos

if [[ ! -x /usr/bin/afplay ]]; then
  echo "afplay not found" >&2
  exit 1
fi

if ! command -v nc >/dev/null 2>&1; then
  echo "nc (netcat) not found" >&2
  exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"
echo $$ >"$PID_FILE"
trap cleanup TERM INT

log "listening on ${BIND_HOST}:${PORT}"

while true; do
  # -k: 连接关闭后继续监听；-l: 监听模式
  if nc -kl -s "$BIND_HOST" "$PORT" >/dev/null 2>>"$LOG_FILE"; then
    play_sound
  fi
  sleep 0.05
done
