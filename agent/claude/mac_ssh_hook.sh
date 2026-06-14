#!/usr/bin/env bash
# mac_ssh_hook.sh — Mac 端 Claude SSH 远程会话结束提示音
#
# 在 Mac 上启动 claude-listener.sh 监听 19999 端口；SSH 到远程 Linux 使用 Claude Code
# 时，SessionEnd hook 经 SSH 反向隧道通知 Mac，播放 Funk.aiff 系统提示音。
#
# Usage:
#   ./mac_ssh_hook.sh install              # 配置开机自启并启动 listener
#   ./mac_ssh_hook.sh uninstall            # 移除自启并停止 listener
#   ./mac_ssh_hook.sh start                # 后台启动 listener
#   ./mac_ssh_hook.sh stop                 # 停止 listener
#   ./mac_ssh_hook.sh restart              # 重启 listener
#   ./mac_ssh_hook.sh status               # 查看运行状态
#   ./mac_ssh_hook.sh test                 # 本地测试播放提示音
#   ./mac_ssh_hook.sh setup-remote [user@host]  # 在远程 Linux 安装 SessionEnd hook
#   ./mac_ssh_hook.sh ssh-hint [user@host] # 打印带反向隧道的 SSH 命令
#   ./mac_ssh_hook.sh help
#
# Environment:
#   CLAUDE_LISTENER_PORT       监听端口（默认 19999）
#   CLAUDE_LISTENER_SOUND      提示音路径（默认 Funk.aiff）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LISTENER_SCRIPT="${SCRIPT_DIR}/claude-listener.sh"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}▶ $*${NC}"; }

PORT="${CLAUDE_LISTENER_PORT:-19999}"
SOUND="${CLAUDE_LISTENER_SOUND:-/System/Library/Sounds/Funk.aiff}"
PID_FILE="${CLAUDE_LISTENER_PID_FILE:-/tmp/claude-listener.pid}"
LOG_FILE="${CLAUDE_LISTENER_LOG_FILE:-/tmp/claude-listener.log}"
LAUNCH_AGENT_LABEL="com.devtools.claude-listener"
LAUNCH_AGENT_PLIST="${HOME}/Library/LaunchAgents/${LAUNCH_AGENT_LABEL}.plist"
REMOTE_HOOK_NAME="session-end-notify-mac.sh"
REMOTE_HOOK_PATH="\${HOME}/.claude/hooks/${REMOTE_HOOK_NAME}"

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || {
    error "此脚本仅支持 macOS"
    exit 1
  }
}

require_listener_script() {
  [[ -x "$LISTENER_SCRIPT" ]] || {
    error "未找到 listener 脚本: $LISTENER_SCRIPT"
    exit 1
  }
}

is_listener_running() {
  [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

port_listening() {
  local host="$1" port="$2"
  nc -G 2 -z "$host" "$port" >/dev/null 2>&1
}

launchctl_domain() {
  echo "gui/$(id -u)"
}

launchctl_load_agent() {
  launchctl bootout "$(launchctl_domain)/${LAUNCH_AGENT_LABEL}" 2>/dev/null \
    || launchctl unload "$LAUNCH_AGENT_PLIST" 2>/dev/null \
    || true
  launchctl bootstrap "$(launchctl_domain)" "$LAUNCH_AGENT_PLIST" 2>/dev/null \
    || launchctl load -w "$LAUNCH_AGENT_PLIST"
}

launchctl_unload_agent() {
  launchctl bootout "$(launchctl_domain)/${LAUNCH_AGENT_LABEL}" 2>/dev/null \
    || launchctl unload "$LAUNCH_AGENT_PLIST" 2>/dev/null \
    || true
}

write_launch_agent() {
  mkdir -p "${HOME}/Library/LaunchAgents"
  cat >"$LAUNCH_AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LAUNCH_AGENT_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${LISTENER_SCRIPT}</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>CLAUDE_LISTENER_PORT</key>
        <string>${PORT}</string>
        <key>CLAUDE_LISTENER_SOUND</key>
        <string>${SOUND}</string>
        <key>CLAUDE_LISTENER_PID_FILE</key>
        <string>${PID_FILE}</string>
        <key>CLAUDE_LISTENER_LOG_FILE</key>
        <string>${LOG_FILE}</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_FILE}</string>
    <key>StandardErrorPath</key>
    <string>${LOG_FILE}</string>
    <key>ThrottleInterval</key>
    <integer>5</integer>
</dict>
</plist>
PLIST
}

cmd_start() {
  require_listener_script

  if is_listener_running; then
    warn "listener 已在运行 (PID $(cat "$PID_FILE"))"
    return 0
  fi

  step "启动 claude-listener (127.0.0.1:${PORT})"
  CLAUDE_LISTENER_PORT="$PORT" \
  CLAUDE_LISTENER_SOUND="$SOUND" \
  CLAUDE_LISTENER_PID_FILE="$PID_FILE" \
  CLAUDE_LISTENER_LOG_FILE="$LOG_FILE" \
    nohup "$LISTENER_SCRIPT" >>"$LOG_FILE" 2>&1 &

  sleep 0.5
  if is_listener_running && port_listening 127.0.0.1 "$PORT"; then
    success "listener 已启动 (PID $(cat "$PID_FILE"))"
  else
    error "listener 启动失败，查看日志: $LOG_FILE"
    exit 1
  fi
}

cmd_stop() {
  step "停止 claude-listener"

  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE")"
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      sleep 0.3
      kill -9 "$pid" 2>/dev/null || true
      success "listener 已停止 (PID $pid)"
    else
      warn "PID $pid 不存在"
    fi
    rm -f "$PID_FILE"
  else
    warn "listener 未运行"
  fi

  pkill -f "claude-listener.sh" 2>/dev/null || true
}

cmd_restart() {
  cmd_stop
  cmd_start
}

cmd_status() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Claude SSH Hook / Listener 状态"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  端口:     ${PORT}"
  echo "  提示音:   ${SOUND}"
  echo "  PID 文件: ${PID_FILE}"
  echo "  日志:     ${LOG_FILE}"
  echo ""

  if is_listener_running; then
    success "listener 运行中 (PID $(cat "$PID_FILE"))"
  else
    warn "listener 未运行"
  fi

  if port_listening 127.0.0.1 "$PORT"; then
    success "127.0.0.1:${PORT} 正在监听"
  else
    warn "127.0.0.1:${PORT} 未监听"
  fi

  if [[ -f "$LAUNCH_AGENT_PLIST" ]]; then
    if launchctl list 2>/dev/null | grep -q "$LAUNCH_AGENT_LABEL"; then
      success "LaunchAgent 已加载: ${LAUNCH_AGENT_LABEL}"
    else
      warn "LaunchAgent plist 存在但未加载"
    fi
  else
    info "LaunchAgent 未安装"
  fi
  echo ""
}

cmd_test() {
  step "测试通知链路"
  if ! port_listening 127.0.0.1 "$PORT"; then
    warn "listener 未运行，先启动..."
    cmd_start
  fi

  if printf 'test\n' | nc -w 2 127.0.0.1 "$PORT" >/dev/null 2>&1; then
    success "已发送测试通知，应听到 Funk.aiff"
  else
    error "无法连接 127.0.0.1:${PORT}"
    exit 1
  fi
}

cmd_play() {
  step "直接播放提示音"
  if [[ -f "$SOUND" ]]; then
    afplay "$SOUND"
    success "已播放: $SOUND"
  else
    error "提示音不存在: $SOUND"
    exit 1
  fi
}

cmd_install() {
  require_listener_script
  step "安装 LaunchAgent 开机自启"
  write_launch_agent
  launchctl_load_agent
  sleep 1
  cmd_status
  echo ""
  info "下一步: 使用 ./mac_ssh_hook.sh ssh-hint user@remote 获取 SSH 命令"
  info "并在远程执行: ./mac_ssh_hook.sh setup-remote user@remote"
}

cmd_uninstall() {
  step "卸载 LaunchAgent"
  launchctl_unload_agent
  rm -f "$LAUNCH_AGENT_PLIST"
  cmd_stop
  success "已卸载自启动并停止 listener"
}

remote_hook_script() {
  cat <<'EOF'
#!/usr/bin/env bash
# Claude Code SessionEnd hook — 通知 Mac 播放提示音
# 需配合 SSH 反向隧道: ssh -R 19999:127.0.0.1:19999 user@remote

set -euo pipefail

PORT="${CLAUDE_MAC_NOTIFY_PORT:-19999}"
HOST="${CLAUDE_MAC_NOTIFY_HOST:-127.0.0.1}"

# 吞掉 stdin（Claude Code 会传入 JSON）
cat >/dev/null || true

if command -v nc >/dev/null 2>&1; then
  printf 'session_end\n' | nc -w 2 "$HOST" "$PORT" >/dev/null 2>&1 || true
elif command -v bash >/dev/null 2>&1; then
  timeout 2 bash -c "echo session_end >/dev/tcp/${HOST}/${PORT}" >/dev/null 2>&1 || true
fi

exit 0
EOF
}

merge_remote_settings() {
  cat <<'EOF'
import json
import os
from pathlib import Path

settings_path = Path.home() / ".claude" / "settings.json"
hook_cmd = str(Path.home() / ".claude" / "hooks" / "session-end-notify-mac.sh")

settings = {}
if settings_path.exists():
    try:
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        settings = {}

hooks = settings.setdefault("hooks", {})
session_end = hooks.setdefault("SessionEnd", [])

entry = {
    "hooks": [
        {
            "type": "command",
            "command": hook_cmd,
        }
    ]
}

if not any(
    item.get("hooks")
    and any(h.get("command") == hook_cmd for h in item["hooks"])
    for item in session_end
):
    session_end.append(entry)

settings_path.parent.mkdir(parents=True, exist_ok=True)
settings_path.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")
print(f"Updated {settings_path}")
EOF
}

cmd_setup_remote() {
  local target="${1:-}"

  if [[ -z "$target" ]]; then
    error "请指定远程主机，例如: ./mac_ssh_hook.sh setup-remote user@linux-host"
    exit 1
  fi

  step "在远程 Linux 安装 Claude SessionEnd hook: $target"

  ssh "$target" "bash -s" <<REMOTE
set -euo pipefail
mkdir -p "\${HOME}/.claude/hooks"
cat > "\${HOME}/.claude/hooks/${REMOTE_HOOK_NAME}" <<'HOOK'
$(remote_hook_script)
HOOK
chmod +x "\${HOME}/.claude/hooks/${REMOTE_HOOK_NAME}"

python3 - <<'PY'
$(merge_remote_settings)
PY
REMOTE

  success "远程 hook 已安装: ~/.claude/hooks/${REMOTE_HOOK_NAME}"
  echo ""
  warn "请确保 SSH 连接带有反向隧道，否则远程无法通知 Mac："
  cmd_ssh_hint "$target"
}

cmd_ssh_hint() {
  local target="${1:-user@remote-host}"
  step "推荐 SSH 命令（含反向隧道）"
  cat <<EOF

  ssh -R ${PORT}:127.0.0.1:${PORT} -o ServerAliveInterval=60 -o ExitOnForwardFailure=yes ${target}

说明:
  1. 在 Mac 上先运行: ./mac_ssh_hook.sh install
  2. 用上述命令 SSH 到远程 Linux
  3. 在远程运行 claude；会话结束时会播放 Mac 上的 Funk.aiff

可选环境变量（远程）:
  CLAUDE_MAC_NOTIFY_PORT=${PORT}
  CLAUDE_MAC_NOTIFY_HOST=127.0.0.1

EOF
}

usage() {
  cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") install              配置开机自启并启动 listener
  $(basename "$0") uninstall            移除自启并停止 listener
  $(basename "$0") start                后台启动 listener
  $(basename "$0") stop                 停止 listener
  $(basename "$0") restart              重启 listener
  $(basename "$0") status               查看状态
  $(basename "$0") test                 发送测试通知
  $(basename "$0") play                 直接播放提示音
  $(basename "$0") setup-remote <host>  远程 Linux 安装 SessionEnd hook
  $(basename "$0") ssh-hint [host]      打印 SSH 反向隧道命令
  $(basename "$0") help

${BOLD}环境变量:${NC}
  CLAUDE_LISTENER_PORT=${PORT}
  CLAUDE_LISTENER_SOUND=${SOUND}

${BOLD}快速开始:${NC}
  ./mac_ssh_hook.sh install
  ./mac_ssh_hook.sh setup-remote user@your-linux
  ./mac_ssh_hook.sh ssh-hint user@your-linux

EOF
}

main() {
  require_macos

  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    install)       cmd_install ;;
    uninstall)     cmd_uninstall ;;
    start)         cmd_start ;;
    stop)          cmd_stop ;;
    restart)       cmd_restart ;;
    status)        cmd_status ;;
    test)          cmd_test ;;
    play)          cmd_play ;;
    setup-remote)  cmd_setup_remote "$@" ;;
    ssh-hint)      cmd_ssh_hint "$@" ;;
    help|-h|--help) usage ;;
    *)
      error "未知命令: $cmd"
      usage
      exit 1
      ;;
  esac
}

main "$@"
