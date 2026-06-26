#!/usr/bin/env bash
# agent-listener.sh — Mac 端通知监听器
#
# 监听本地端口，收到远程 agent 事件通知后播放系统提示音。
# 通常由 mac_ssh_notify.sh 或 launchd 启动，勿直接手动运行（除非调试）。

set -euo pipefail

PORT="${AGENT_NOTIFY_PORT:-${CLAUDE_LISTENER_PORT:-19999}}"
BIND_HOST="${AGENT_NOTIFY_HOST:-${CLAUDE_LISTENER_HOST:-127.0.0.1}}"
SOUND="${AGENT_NOTIFY_SOUND:-${CLAUDE_LISTENER_SOUND:-/System/Library/Sounds/Funk.aiff}}"
PID_FILE="${AGENT_NOTIFY_PID_FILE:-${CLAUDE_LISTENER_PID_FILE:-/tmp/agent-notify-listener.pid}}"
LOG_FILE="${AGENT_NOTIFY_LOG_FILE:-${CLAUDE_LISTENER_LOG_FILE:-/tmp/agent-notify-listener.log}}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_FILE"
}

play_sound() {
  local source="$1"
  local event="$2"

  if [[ -f "$SOUND" ]]; then
    /usr/bin/afplay "$SOUND" &
    log "source=${source} event=${event} played sound: $SOUND"
  else
    log "source=${source} event=${event} sound file not found: $SOUND"
  fi
}

handle_payload() {
  local payload="$1"
  local source="unknown"
  local event="unknown"

  payload="${payload//$'\r'/}"
  payload="${payload//$'\n'/}"

  if [[ -n "$payload" && "$payload" == *:* ]]; then
    source="${payload%%:*}"
    event="${payload#*:}"
  elif [[ -n "$payload" ]]; then
    event="$payload"
  fi

  log "received source=${source} event=${event} payload=${payload:-empty}"
  play_sound "$source" "$event"
}

cleanup() {
  rm -f "$PID_FILE"
  log "listener stopped"
  exit 0
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || {
    echo "agent-listener.sh requires macOS" >&2
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
  payload="$(nc -l -s "$BIND_HOST" "$PORT" 2>>"$LOG_FILE" || true)"
  if [[ -n "$payload" ]]; then
    handle_payload "$payload"
  else
    log "received empty payload"
    play_sound "unknown" "unknown"
  fi
  sleep 0.05
done
