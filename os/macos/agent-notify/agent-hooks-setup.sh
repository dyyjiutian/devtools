#!/usr/bin/env bash
# agent-hooks-setup.sh — Mac 端 agent 事件提示音统一管理
#
# Mac 上启动 agent-listener.sh 监听 127.0.0.1:19999，收到 "source:event" 通知后
# 按来源（claude / codex）播放对应系统提示音。
#
# 通知来源：
#   - 本机 Claude / Codex：hook 直接把消息发到 127.0.0.1:19999
#   - 远端 Linux 的 Claude / Codex：经 SSH 反向隧道 (-R) 回传到 Mac 的 19999
#
# Usage:
#   ./agent-hooks-setup.sh install                    # 仅在本机安装 LaunchAgent 并启动 listener
#   ./agent-hooks-setup.sh uninstall                  # 移除 LaunchAgent 并停止 listener
#   ./agent-hooks-setup.sh test [claude|codex|src]    # 发送一条测试通知
#   ./agent-hooks-setup.sh hook add    <claude|codex|cursor|all> [target]  # 安装 agent 通知 hook
#   ./agent-hooks-setup.sh hook remove <claude|codex|cursor|all> [target]  # 移除 agent 通知 hook
#   ./agent-hooks-setup.sh hook list [target]      # 查看 hook 安装情况
#   ./agent-hooks-setup.sh -h                       # 查看帮助与支持的环境变量
#
# target 省略或写 local/127.0.0.1 表示本机；写 user@host 表示远端（经 SSH 安装）。
#
# Environment:
#   CLIAGENT_HOOK_PORT          监听/通知端口（默认 19999）
#   CLIAGENT_HOOK_SOUND         默认提示音
#   CLIAGENT_HOOK_SOUND_CLAUDE  Claude 提示音（默认 Funk.aiff）
#   CLIAGENT_HOOK_SOUND_CODEX   Codex 提示音（默认 Glass.aiff）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LISTENER_SCRIPT="${SCRIPT_DIR}/agent-listener.sh"

# 与代码库解耦的稳定安装目录；本机 listener 副本与本机 hook 脚本都放这里，
# 远端安装时会在远端 $HOME 下使用同样的相对布局。
CLIAGENT_HOOK_HOME="${CLIAGENT_HOOK_HOME:-${HOME}/.cliagent-hook}"
INSTALLED_LISTENER="${CLIAGENT_HOOK_HOME}/agent-listener.sh"

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

PORT="${CLIAGENT_HOOK_PORT:-${CLAUDE_LISTENER_PORT:-19999}}"
SOUND="${CLIAGENT_HOOK_SOUND:-${CLAUDE_LISTENER_SOUND:-/System/Library/Sounds/Funk.aiff}}"
PID_FILE="${CLIAGENT_HOOK_PID_FILE:-${CLAUDE_LISTENER_PID_FILE:-/tmp/cliagent-hook-listener.pid}}"
LOG_FILE="${CLIAGENT_HOOK_LOG_FILE:-${CLAUDE_LISTENER_LOG_FILE:-/tmp/cliagent-hook-listener.log}}"
LAUNCH_AGENT_LABEL="com.cliagent.hook.listener"
LAUNCH_AGENT_PLIST="${HOME}/Library/LaunchAgents/${LAUNCH_AGENT_LABEL}.plist"

# ────────────────────────────── 通用工具 ──────────────────────────────

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

is_local_target() {
  case "$1" in
    ""|local|localhost|127.0.0.1) return 0 ;;
    *) return 1 ;;
  esac
}

# 在指定 target 上执行从 stdin 读入的 bash 脚本：本机用 bash，远端用 ssh。
exec_on_target() {
  local target="$1"
  if is_local_target "$target"; then
    bash -s
  else
    ssh "$target" "bash -s"
  fi
}

is_listener_running() {
  [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

port_listening() {
  local host="$1" port="$2"
  CLIAGENT_HOOK_PROBE_HOST="$host" CLIAGENT_HOOK_PROBE_PORT="$port" python3 -c '
import os
import socket

host = os.environ["CLIAGENT_HOOK_PROBE_HOST"]
port = int(os.environ["CLIAGENT_HOOK_PROBE_PORT"])
with socket.create_connection((host, port), timeout=2):
    pass
' >/dev/null 2>&1
}

send_payload() {
  local host="$1" port="$2"
  CLIAGENT_HOOK_SEND_HOST="$host" CLIAGENT_HOOK_SEND_PORT="$port" python3 -c '
import os
import socket
import sys

host = os.environ["CLIAGENT_HOOK_SEND_HOST"]
port = int(os.environ["CLIAGENT_HOOK_SEND_PORT"])
payload = sys.stdin.buffer.read()
if not payload.endswith(b"\n"):
    payload += b"\n"
with socket.create_connection((host, port), timeout=2) as sock:
    sock.settimeout(2)
    sock.sendall(payload)
    sock.shutdown(socket.SHUT_WR)
'
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

install_listener_copy() {
  mkdir -p "$CLIAGENT_HOOK_HOME"
  cp "$LISTENER_SCRIPT" "$INSTALLED_LISTENER"
  chmod +x "$INSTALLED_LISTENER"
  info "已复制 listener 到稳定位置: $INSTALLED_LISTENER"
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
        <string>${INSTALLED_LISTENER}</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>CLIAGENT_HOOK_PORT</key>
        <string>${PORT}</string>
        <key>CLIAGENT_HOOK_SOUND</key>
        <string>${SOUND}</string>
        <key>CLIAGENT_HOOK_PID_FILE</key>
        <string>${PID_FILE}</string>
        <key>CLIAGENT_HOOK_LOG_FILE</key>
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

# ────────────────────────────── listener 生命周期 ──────────────────────────────

cmd_start() {
  require_listener_script

  if is_listener_running; then
    warn "listener 已在运行 (PID $(cat "$PID_FILE"))"
    return 0
  fi

  step "启动 cliagent-hook-listener (127.0.0.1:${PORT})"
  CLIAGENT_HOOK_PORT="$PORT" \
  CLIAGENT_HOOK_SOUND="$SOUND" \
  CLIAGENT_HOOK_PID_FILE="$PID_FILE" \
  CLIAGENT_HOOK_LOG_FILE="$LOG_FILE" \
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
  step "停止 cliagent-hook-listener"

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

  pkill -f "agent-listener.sh" 2>/dev/null || true
}

cmd_status() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Agent Notify / Listener 状态"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  端口:     ${PORT}"
  echo "  提示音:   ${SOUND}（claude/codex 共用，来源用系统通知区分）"
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
    if [[ -x "$INSTALLED_LISTENER" ]]; then
      success "listener 副本: ${INSTALLED_LISTENER}"
    else
      warn "listener 副本缺失: ${INSTALLED_LISTENER}（请重新 install）"
    fi
  else
    info "LaunchAgent 未安装"
  fi
  echo ""
}

# ────────────────────────────── install / uninstall ──────────────────────────────

cmd_install() {
  require_listener_script
  step "安装 LaunchAgent 开机自启（仅本机 listener）"
  install_listener_copy
  write_launch_agent
  launchctl_load_agent
  sleep 1
  cmd_status
  echo ""
  info "接下来给本机或远端的 agent 安装 hook，例如："
  info "  ./agent-hooks-setup.sh hook add all              # 本机 Claude + Codex"
  info "  ./agent-hooks-setup.sh hook add all user@remote  # 远端 Claude + Codex"
}

cmd_uninstall() {
  step "卸载 LaunchAgent 并停止 listener"
  launchctl_unload_agent
  rm -f "$LAUNCH_AGENT_PLIST"
  cmd_stop
  rm -f "$INSTALLED_LISTENER"
  rmdir "$CLIAGENT_HOOK_HOME" 2>/dev/null || true
  success "已卸载自启动并停止 listener"
  echo ""
  info "如需移除已安装的 agent hook: ./agent-hooks-setup.sh hook remove all [user@host]"
}

# ────────────────────────────── test ──────────────────────────────

cmd_test() {
  local source="${1:-manual}"

  step "发送测试通知 (${source})"
  is_listener_running || { warn "listener 未运行，先启动..."; cmd_start; }

  local origin payload
  origin="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
  payload="$(SRC="$source" ORG="$origin" CWD="$PWD" python3 -c \
    'import os,json;print(json.dumps({"source":os.environ["SRC"],"event":"test","origin":os.environ["ORG"],"cwd":os.environ["CWD"],"message":"测试通知"},ensure_ascii=False))')"

  if printf '%s\n' "$payload" | send_payload 127.0.0.1 "$PORT" >/dev/null 2>&1; then
    success "已发送测试通知"
  else
    error "无法连接 127.0.0.1:${PORT}"
    exit 1
  fi
}

# ────────────────────────────── hook 脚本内容 ──────────────────────────────

hook_sender_content() {
  cat <<'EOF'
send_notification() {
  local message="$1"
  printf '%s\n' "$message" |
    CLIAGENT_HOOK_SEND_HOST="$HOST" CLIAGENT_HOOK_SEND_PORT="$PORT" python3 -c '
import os
import socket
import sys

host = os.environ["CLIAGENT_HOOK_SEND_HOST"]
port = int(os.environ["CLIAGENT_HOOK_SEND_PORT"])
payload = sys.stdin.buffer.read()
with socket.create_connection((host, port), timeout=2) as sock:
    sock.settimeout(2)
    sock.sendall(payload)
    sock.shutdown(socket.SHUT_WR)
'
}
EOF
}

claude_hook_content() {
  cat <<'EOF'
#!/usr/bin/env bash
# Claude Code hook — 发送单行 JSON 给 agent listener
# 本机: 发到 127.0.0.1:19999；远端: 经 SSH 反向隧道回传 Mac
set -euo pipefail
command -v python3 >/dev/null 2>&1 || exit 0

PORT="${CLIAGENT_HOOK_PORT:-19999}"
HOST="${CLIAGENT_HOOK_HOST:-127.0.0.1}"
EVENT="${1:-stop}"

EOF
  hook_sender_content
  cat <<'EOF'

MSG="$(EVENT="$EVENT" python3 -c '
import sys, os, json, socket
ev = os.environ["EVENT"]
try:
    d = json.loads(sys.stdin.read() or "{}")
except Exception:
    d = {}
cwd = d.get("cwd", "") or os.getcwd()

def session_title(path):
    # session 标题：取首条真实用户消息（跳过命令/系统注入）
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    e = json.loads(line)
                except Exception:
                    continue
                if e.get("type") != "user":
                    continue
                c = e.get("message", {}).get("content")
                t = ""
                if isinstance(c, str):
                    t = c
                elif isinstance(c, list):
                    for it in c:
                        if isinstance(it, dict) and it.get("type") == "text":
                            t += it.get("text", "")
                t = " ".join(t.split())
                if t and not t.startswith("<") and not t.startswith("Caveat:"):
                    return t
    except Exception:
        pass
    return ""

if ev == "notification":
    body = " ".join((d.get("message") or "Input Needed").split())
else:
    title = session_title(d.get("transcript_path", ""))
    if len(title) > 40:
        title = title[:40] + "…"
    body = title  # 为空时由 listener 回退为 Session Completed
print(json.dumps({"source": "claude", "event": ev,
                  "origin": socket.gethostname().split(".")[0],
                  "cwd": cwd, "message": body}, ensure_ascii=False))
')"

send_notification "$MSG" >/dev/null 2>&1 || true
exit 0
EOF
}

codex_hook_content() {
  cat <<'EOF'
#!/usr/bin/env bash
# Codex CLI notify — 发送单行 JSON 给 agent listener
# Codex 以 JSON 字符串作为 $1 传入事件（含 type / cwd / input-messages 等）
set -euo pipefail
command -v python3 >/dev/null 2>&1 || exit 0

PORT="${CLIAGENT_HOOK_PORT:-19999}"
HOST="${CLIAGENT_HOOK_HOST:-127.0.0.1}"

EOF
  hook_sender_content
  cat <<'EOF'

MSG="$(python3 -c '
import sys, os, json, socket
try:
    d = json.loads(sys.argv[1]) if len(sys.argv) > 1 else {}
except Exception:
    d = {}
event = str(d.get("type", "agent-turn-complete")).replace("-", "_")
cwd = d.get("cwd", "") or ""
def first(v):
    if isinstance(v, list):
        for x in v:
            if isinstance(x, str) and x.strip():
                return x
    return v if isinstance(v, str) else ""
t = " ".join(first(d.get("input-messages") or d.get("last-assistant-message")).split())
if len(t) > 40:
    t = t[:40] + "…"
body = t  # 为空时由 listener 回退为 Session Completed
print(json.dumps({"source": "codex", "event": event,
                  "origin": socket.gethostname().split(".")[0],
                  "cwd": cwd, "message": body}, ensure_ascii=False))
' "${1:-}")"

send_notification "$MSG" >/dev/null 2>&1 || true
exit 0
EOF
}

cursor_hook_content() {
  cat <<'EOF'
#!/usr/bin/env bash
# Cursor Agent CLI hook (stop) — 发送单行 JSON 给 agent listener
set -euo pipefail
command -v python3 >/dev/null 2>&1 || exit 0

PORT="${CLIAGENT_HOOK_PORT:-19999}"
HOST="${CLIAGENT_HOOK_HOST:-127.0.0.1}"

EOF
  hook_sender_content
  cat <<'EOF'

MSG="$(python3 -c '
import sys, os, json, socket, glob
try:
    d = json.loads(sys.stdin.read() or "{}")
except Exception:
    d = {}
# stop payload 无 cwd，取 workspace_roots[0]
cwd = d.get("cwd", "")
if not cwd:
    wr = d.get("workspace_roots") or d.get("workspaceRoots")
    if isinstance(wr, list) and wr:
        cwd = wr[0]
# 会话标题：conversation_id -> ~/.cursor/chats/*/<id>/meta.json 的 title（未文档化，尽力而为）
title = ""
conv = d.get("conversation_id") or d.get("conversationId") or ""
if conv:
    pat = os.path.expanduser(os.path.join("~", ".cursor", "chats", "*", conv, "meta.json"))
    for mp in glob.glob(pat):
        try:
            with open(mp, encoding="utf-8") as fh:
                m = json.load(fh)
            title = (m.get("title") or "").strip() or title
            if not cwd:
                cwd = m.get("cwd", "") or cwd
        except Exception:
            pass
title = " ".join(title.split())
if len(title) > 40:
    title = title[:40] + "…"
print(json.dumps({"source": "cursor", "event": "stop",
                  "origin": socket.gethostname().split(".")[0],
                  "cwd": cwd, "message": title}, ensure_ascii=False))
')"

send_notification "$MSG" >/dev/null 2>&1 || true
exit 0
EOF
}

# 在目标 ~/.cursor/hooks.json 中增删 stop hook（add|remove 通过 argv 传入）
cursor_hooks_json_py() {
  cat <<'EOF'
import json, sys
from pathlib import Path

action = sys.argv[1] if len(sys.argv) > 1 else "add"
path = Path.home() / ".cursor" / "hooks.json"
cmd = str(Path.home() / ".cliagent-hook" / "hooks" / "cliagent-hook-cursor.sh")

data = {}
if path.exists():
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        data = {}
if not isinstance(data, dict):
    data = {}

data.setdefault("version", 1)
hooks = data.setdefault("hooks", {})
arr = hooks.get("stop", [])
if not isinstance(arr, list):
    arr = []


def matches(it):
    return isinstance(it, dict) and it.get("command") == cmd


if action == "add":
    if not any(matches(it) for it in arr):
        arr.append({"command": cmd})
    hooks["stop"] = arr
else:
    arr = [it for it in arr if not matches(it)]
    if arr:
        hooks["stop"] = arr
    else:
        hooks.pop("stop", None)

path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print(f"{action} cursor stop hook -> {path}")
EOF
}

# 在目标 ~/.claude/settings.json 中增删 Stop / Notification hook（add|remove 通过 argv 传入）
claude_settings_py() {
  cat <<'EOF'
import json, sys
from pathlib import Path

action = sys.argv[1] if len(sys.argv) > 1 else "add"
settings_path = Path.home() / ".claude" / "settings.json"
base = str(Path.home() / ".cliagent-hook" / "hooks" / "cliagent-hook-claude.sh")

# 事件 -> 传给 hook 的参数（Stop=一轮结束，Notification=需要输入）
event_args = {"Stop": "stop", "Notification": "notification"}

settings = {}
if settings_path.exists():
    try:
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        settings = {}

hooks = settings.get("hooks", {})

for event, arg in event_args.items():
    hook_cmd = f"{base} {arg}"
    arr = hooks.get(event, [])

    def matches(item):
        return (
            isinstance(item, dict)
            and isinstance(item.get("hooks"), list)
            and any(
                isinstance(hook, dict) and hook.get("command") == hook_cmd
                for hook in item["hooks"]
            )
        )

    if action == "add":
        found = False
        for item in arr:
            if not matches(item):
                continue
            for hook in item["hooks"]:
                if isinstance(hook, dict) and hook.get("command") == hook_cmd:
                    hook["type"] = "command"
                    hook["timeout"] = 10
                    found = True
        if not found:
            arr.append(
                {
                    "hooks": [
                        {"type": "command", "command": hook_cmd, "timeout": 10}
                    ]
                }
            )
        hooks[event] = arr
    else:
        arr = [it for it in arr if not matches(it)]
        if arr:
            hooks[event] = arr
        else:
            hooks.pop(event, None)

if hooks:
    settings["hooks"] = hooks
else:
    settings.pop("hooks", None)

settings_path.parent.mkdir(parents=True, exist_ok=True)
settings_path.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")
print(f"{action} claude Stop/Notification hooks -> {settings_path}")
EOF
}

# 在目标 ~/.codex/config.toml 中增删 notify（用托管块包裹，add|remove 通过 argv 传入）
codex_config_py() {
  cat <<'EOF'
import sys
from pathlib import Path

action = sys.argv[1] if len(sys.argv) > 1 else "add"
cfg = Path.home() / ".codex" / "config.toml"
script = str(Path.home() / ".cliagent-hook" / "hooks" / "cliagent-hook-codex.sh")
BEGIN = "# >>> cliagent-hook BEGIN <<<"
END = "# >>> cliagent-hook END <<<"

text = cfg.read_text(encoding="utf-8") if cfg.exists() else ""
lines = text.splitlines()

# 移除已有托管块
out = []
skip = False
for ln in lines:
    st = ln.strip()
    if st == BEGIN:
        skip = True
        continue
    if st == END:
        skip = False
        continue
    if not skip:
        out.append(ln)

# 去掉块移除后残留的前导空行，避免重复 add 时空行累积
while out and out[0].strip() == "":
    out.pop(0)

if action == "add":
    # 去掉托管块外已有的顶层 notify，避免 TOML 重复键
    cleaned = []
    in_table = False
    for ln in out:
        st = ln.strip()
        if st.startswith("[") and st.endswith("]"):
            in_table = True
        if (not in_table) and (st.startswith("notify ") or st.startswith("notify=")):
            continue
        cleaned.append(ln)
    block = [BEGIN, 'notify = ["%s"]' % script, END, ""]
    new_lines = block + cleaned
else:
    new_lines = out

result = "\n".join(new_lines).rstrip("\n") + "\n"
cfg.parent.mkdir(parents=True, exist_ok=True)
cfg.write_text(result, encoding="utf-8")
print("%s codex notify -> %s" % (action, cfg))
EOF
}

# ────────────────────────────── hook 安装/卸载 ──────────────────────────────

apply_claude_hook() {
  local action="$1" target="$2"
  local where; is_local_target "$target" && where="本机" || where="$target"
  step "${action} Claude hook (${where})"

  if [[ "$action" == "add" ]]; then
    exec_on_target "$target" <<REMOTE
set -euo pipefail
HOOKS_DIR="\${HOME}/.cliagent-hook/hooks"
mkdir -p "\$HOOKS_DIR"
cat > "\$HOOKS_DIR/cliagent-hook-claude.sh" <<'HOOK'
$(claude_hook_content)
HOOK
chmod +x "\$HOOKS_DIR/cliagent-hook-claude.sh"
python3 - add <<'PY'
$(claude_settings_py)
PY
REMOTE
  else
    exec_on_target "$target" <<REMOTE
set -euo pipefail
python3 - remove <<'PY'
$(claude_settings_py)
PY
rm -f "\${HOME}/.cliagent-hook/hooks/cliagent-hook-claude.sh"
REMOTE
  fi
  success "Claude hook ${action} 完成 (${where})"
}

apply_codex_hook() {
  local action="$1" target="$2"
  local where; is_local_target "$target" && where="本机" || where="$target"
  step "${action} Codex notify (${where})"

  if [[ "$action" == "add" ]]; then
    exec_on_target "$target" <<REMOTE
set -euo pipefail
HOOKS_DIR="\${HOME}/.cliagent-hook/hooks"
mkdir -p "\$HOOKS_DIR"
cat > "\$HOOKS_DIR/cliagent-hook-codex.sh" <<'HOOK'
$(codex_hook_content)
HOOK
chmod +x "\$HOOKS_DIR/cliagent-hook-codex.sh"
python3 - add <<'PY'
$(codex_config_py)
PY
REMOTE
  else
    exec_on_target "$target" <<REMOTE
set -euo pipefail
python3 - remove <<'PY'
$(codex_config_py)
PY
rm -f "\${HOME}/.cliagent-hook/hooks/cliagent-hook-codex.sh"
REMOTE
  fi
  success "Codex notify ${action} 完成 (${where})"
}

apply_cursor_hook() {
  local action="$1" target="$2"
  local where; is_local_target "$target" && where="本机" || where="$target"
  step "${action} Cursor hook (${where})"

  if [[ "$action" == "add" ]]; then
    exec_on_target "$target" <<REMOTE
set -euo pipefail
HOOKS_DIR="\${HOME}/.cliagent-hook/hooks"
mkdir -p "\$HOOKS_DIR"
cat > "\$HOOKS_DIR/cliagent-hook-cursor.sh" <<'HOOK'
$(cursor_hook_content)
HOOK
chmod +x "\$HOOKS_DIR/cliagent-hook-cursor.sh"
python3 - add <<'PY'
$(cursor_hooks_json_py)
PY
REMOTE
  else
    exec_on_target "$target" <<REMOTE
set -euo pipefail
python3 - remove <<'PY'
$(cursor_hooks_json_py)
PY
rm -f "\${HOME}/.cliagent-hook/hooks/cliagent-hook-cursor.sh"
REMOTE
  fi
  success "Cursor hook ${action} 完成 (${where})"
}

list_hooks() {
  local target="${1:-local}"
  local where; is_local_target "$target" && where="本机" || where="$target"
  step "查看 hook 安装情况 (${where})"

  exec_on_target "$target" <<'REMOTE'
set -euo pipefail
HOOKS_DIR="${HOME}/.cliagent-hook/hooks"
echo "hooks 目录: $HOOKS_DIR"
[[ -f "$HOOKS_DIR/cliagent-hook-claude.sh" ]] && echo "  [x] cliagent-hook-claude.sh" || echo "  [ ] cliagent-hook-claude.sh"
[[ -f "$HOOKS_DIR/cliagent-hook-codex.sh" ]]  && echo "  [x] cliagent-hook-codex.sh"  || echo "  [ ] cliagent-hook-codex.sh"
[[ -f "$HOOKS_DIR/cliagent-hook-cursor.sh" ]] && echo "  [x] cliagent-hook-cursor.sh" || echo "  [ ] cliagent-hook-cursor.sh"

CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
if [[ -f "$CLAUDE_SETTINGS" ]] && grep -q "cliagent-hook-claude.sh" "$CLAUDE_SETTINGS" 2>/dev/null; then
  echo "  [x] Claude settings.json 已挂 Stop/Notification hook"
else
  echo "  [ ] Claude settings.json 未挂 hook"
fi

CODEX_CFG="${HOME}/.codex/config.toml"
if [[ -f "$CODEX_CFG" ]] && grep -q "cliagent-hook-codex.sh" "$CODEX_CFG" 2>/dev/null; then
  echo "  [x] Codex config.toml 已设置 notify"
else
  echo "  [ ] Codex config.toml 未设置 notify"
fi

CURSOR_HOOKS="${HOME}/.cursor/hooks.json"
if [[ -f "$CURSOR_HOOKS" ]] && grep -q "cliagent-hook-cursor.sh" "$CURSOR_HOOKS" 2>/dev/null; then
  echo "  [x] Cursor hooks.json 已挂 stop hook"
else
  echo "  [ ] Cursor hooks.json 未挂 hook"
fi
REMOTE
}

cmd_hook() {
  local action="${1:-}"
  local agent="${2:-}"
  local target="${3:-local}"

  case "$action" in
    add|install)   action="add" ;;
    remove|rm|uninstall) action="remove" ;;
    list|ls)
      list_hooks "${2:-local}"
      hook_epilogue "$action" "${2:-local}"
      return 0
      ;;
    *)
      error "hook 子命令需为 add | remove | list"
      usage
      exit 1
      ;;
  esac

  case "$agent" in
    claude) apply_claude_hook "$action" "$target" ;;
    codex)  apply_codex_hook  "$action" "$target" ;;
    cursor) apply_cursor_hook "$action" "$target" ;;
    all)
      apply_claude_hook "$action" "$target"
      apply_codex_hook  "$action" "$target"
      apply_cursor_hook "$action" "$target"
      ;;
    *)
      error "agent 需为 claude | codex | cursor | all"
      usage
      exit 1
      ;;
  esac

  hook_epilogue "$action" "$target"
}

hook_epilogue() {
  local action="$1" target="$2"
  echo ""
  if [[ "$action" == "add" ]] && ! is_local_target "$target"; then
    configure_ssh_remote_forward "$target"
    echo ""
    warn "远端通知需带反向隧道的 SSH 连接，否则无法回传 Mac："
    print_ssh_hint "$target"
  fi
}

# ────────────────────────────── help ──────────────────────────────

# 若 ~/.ssh/config 已存在该 host 的 Host 条目，则补上 RemoteForward（幂等）
configure_ssh_remote_forward() {
  local target="$1"
  local host="${target#*@}"
  host="${host%%:*}"
  local cfg="${HOME}/.ssh/config"

  [[ -f "$cfg" ]] || { info "未找到 ~/.ssh/config，跳过 RemoteForward 配置"; return 0; }

  local result
  result="$(HOST="$host" PORT="$PORT" CFG="$cfg" python3 -c '
import os, re, sys, shutil, datetime
host, port, cfg = os.environ["HOST"], os.environ["PORT"], os.environ["CFG"]
fwd = "RemoteForward %s 127.0.0.1:%s" % (port, port)
lines = open(cfg, encoding="utf-8").read().split("\n")

def block_end(idx):
    for j in range(idx + 1, len(lines)):
        if re.match(r"\s*(Host|Match)\s+", lines[j], re.I):
            return j
    return len(lines)

# 匹配 Host 别名或块内 HostName 值
start = end = None
for i, ln in enumerate(lines):
    m = re.match(r"\s*Host\s+(.+?)\s*$", ln, re.I)
    if not m:
        continue
    e = block_end(i)
    pats = m.group(1).split()
    hostname = ""
    for bl in lines[i + 1:e]:
        hm = re.match(r"\s*HostName\s+(\S+)", bl, re.I)
        if hm:
            hostname = hm.group(1); break
    if host in pats or (hostname and host == hostname):
        start, end = i, e
        break

if start is None:
    print("NOTINCONFIG"); sys.exit(0)

for ln in lines[start:end]:
    m = re.match(r"\s*RemoteForward\s+(\S+)\s+", ln, re.I)
    if m and m.group(1) == port:
        print("EXISTS"); sys.exit(0)

indent = "    "
for ln in lines[start + 1:end]:
    m = re.match(r"(\s+)\S", ln)
    if m:
        indent = m.group(1); break

shutil.copy2(cfg, cfg + ".bak." + datetime.datetime.now().strftime("%Y%m%d%H%M%S"))
lines.insert(start + 1, indent + fwd)
open(cfg, "w", encoding="utf-8").write("\n".join(lines))
print("ADDED")
')" || { warn "处理 ~/.ssh/config 失败，跳过"; return 0; }

  case "$result" in
    ADDED)       success "已在 ~/.ssh/config 的 Host ${host} 补上 RemoteForward ${PORT}（原文件已备份）" ;;
    EXISTS)      info "~/.ssh/config 的 Host ${host} 已有 RemoteForward ${PORT}，跳过" ;;
    NOTINCONFIG) warn "~/.ssh/config 无 Host ${host} 条目，未修改（可手动添加）" ;;
    *)           warn "RemoteForward 配置返回未知结果：${result}" ;;
  esac
}

print_ssh_hint() {
  local target="${1:-user@your-linux}"
  cat <<EOF

  ssh -R ${PORT}:127.0.0.1:${PORT} -o ServerAliveInterval=60 -o ExitOnForwardFailure=yes ${target}

  或在 ~/.ssh/config 中：
    Host dev-linux
        HostName your-linux-host
        User your-user
        RemoteForward ${PORT} 127.0.0.1:${PORT}
        ServerAliveInterval 60
        ExitOnForwardFailure yes

EOF
}

usage() {
  cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") install                              仅在本机安装 LaunchAgent 并启动 listener
  $(basename "$0") uninstall                            移除 LaunchAgent 并停止 listener
  $(basename "$0") test [claude|codex|src]              发送一条测试通知（默认 source=manual）
  $(basename "$0") hook add    <claude|codex|cursor|all> [target]  安装 agent 通知 hook
  $(basename "$0") hook remove <claude|codex|cursor|all> [target]  移除 agent 通知 hook
  $(basename "$0") hook list [target]                              查看 hook 安装情况

  target 省略或 local/127.0.0.1 = 本机；user@host = 远端（经 SSH 安装）
  -h, --help                                                       显示本帮助（含环境变量）

${BOLD}提示音:${NC}
  声音    = ${SOUND}（claude / codex 共用）
  区分    = 系统通知横幅标题（Claude Code / Codex）
  端口    = ${PORT}

${BOLD}环境变量（可自定义端口等，install 时会写入 LaunchAgent）:${NC}
  CLIAGENT_HOOK_PORT       监听/通知端口（默认 19999）
  CLIAGENT_HOOK_HOST       监听/通知地址（默认 127.0.0.1）
  CLIAGENT_HOOK_SOUND      默认提示音（默认 /System/Library/Sounds/Funk.aiff）
  CLIAGENT_HOOK_HOME       listener 副本与 hook 脚本安装目录（默认 ~/.cliagent-hook）
  CLIAGENT_HOOK_PID_FILE   listener PID 文件（默认 /tmp/cliagent-hook-listener.pid）
  CLIAGENT_HOOK_LOG_FILE   listener 日志文件（默认 /tmp/cliagent-hook-listener.log）

  示例：自定义监听端口为 28888
    CLIAGENT_HOOK_PORT=28888 ./$(basename "$0") install
    CLIAGENT_HOOK_PORT=28888 ./$(basename "$0") hook add all user@your-linux

${BOLD}SSH 登录示例（远端 agent 通知必须带反向隧道 -R）:${NC}
$(print_ssh_hint user@your-linux)
${BOLD}快速开始:${NC}
  # 本机场景
  1. ./agent-hooks-setup.sh install
  2. ./agent-hooks-setup.sh hook add all         # 给本机 Claude + Codex 装 hook
  3. 正常使用 claude / codex，完成时会听到提示音

  # 远端 Linux 场景
  1. ./agent-hooks-setup.sh install
  2. ./agent-hooks-setup.sh hook add all user@your-linux
  3. 用上面的 SSH 命令登录远端，再运行 claude / codex

EOF
}

# ────────────────────────────── 入口 ──────────────────────────────

main() {
  local cmd="${1:-}"
  shift || true

  # help / 无参数不依赖 macOS，方便随处查看用法与环境变量
  case "$cmd" in
    ""|-h|--help) usage; return 0 ;;
  esac

  require_macos

  case "$cmd" in
    install)        cmd_install ;;
    uninstall)      cmd_uninstall ;;
    test)           cmd_test "$@" ;;
    hook)           cmd_hook "$@" ;;
    *)
      error "未知命令: $cmd"
      usage
      exit 1
      ;;
  esac
}

if [[ "${SETUP_NO_MAIN:-false}" != "true" && "${SETUP_NO_MAIN:-false}" != "1" ]]; then
  main "$@"
fi
