#!/usr/bin/env bash
# agent-listener.sh — Mac 端通知监听器（python3 socket server）
#
# 监听本地端口，收到单行 JSON 通知后播放提示音并弹系统通知横幅。
# 通常由 agent-hooks-setup.sh 或 launchd 启动，勿直接手动运行（除非调试）。
#
# 协议（单行 JSON）：{"source","event","origin","cwd","message"}
# 通知映射：title=应用名，subtitle=项目名 · 会话标题(message)，body=Local/Remote · 主机名。

set -euo pipefail

PORT="${CLIAGENT_HOOK_PORT:-19999}"
BIND_HOST="${CLIAGENT_HOOK_HOST:-127.0.0.1}"
SOUND="${CLIAGENT_HOOK_SOUND:-/System/Library/Sounds/Funk.aiff}"
PID_FILE="${CLIAGENT_HOOK_PID_FILE:-/tmp/cliagent-hook-listener.pid}"
LOG_FILE="${CLIAGENT_HOOK_LOG_FILE:-/tmp/cliagent-hook-listener.log}"
LOCAL_HOST="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo localhost)"

[[ "$(uname -s)" == "Darwin" ]] || { echo "requires macOS" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found" >&2; exit 1; }

mkdir -p "$(dirname "$LOG_FILE")"
echo $$ >"$PID_FILE"

export CLIAGENT_HOOK_PORT="$PORT" CLIAGENT_HOOK_HOST="$BIND_HOST" CLIAGENT_HOOK_SOUND="$SOUND" \
  CLIAGENT_HOOK_PID_FILE="$PID_FILE" CLIAGENT_HOOK_LOG_FILE="$LOG_FILE" CLIAGENT_HOOK_LOCAL_HOST="$LOCAL_HOST"

# 用 $0 作为占位 argv，让 ps/pkill 仍能通过 "agent-listener.sh" 匹配到进程
exec python3 - "$0" <<'PY'
import os, socket, subprocess, json, signal, sys, datetime

PORT = int(os.environ.get("CLIAGENT_HOOK_PORT", "19999"))
HOST = os.environ.get("CLIAGENT_HOOK_HOST", "127.0.0.1")
SOUND = os.environ.get("CLIAGENT_HOOK_SOUND", "/System/Library/Sounds/Funk.aiff")
LOG_FILE = os.environ.get("CLIAGENT_HOOK_LOG_FILE", "/tmp/cliagent-hook-listener.log")
PID_FILE = os.environ.get("CLIAGENT_HOOK_PID_FILE", "/tmp/cliagent-hook-listener.pid")
LOCAL_HOST = os.environ.get("CLIAGENT_HOOK_LOCAL_HOST", "")
TITLES = {"claude": "Claude Code", "codex": "Codex", "cursor": "Cursor Agent"}


def log(msg):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write("[%s] %s\n" % (ts, msg))
    except Exception:
        pass


def clean(s):
    return " ".join(str(s if s is not None else "").split())


def handle(payload):
    if not payload.strip():
        log("ignored empty payload")
        return
    try:
        d = json.loads(payload)
    except Exception:
        log("ignored non-json payload")
        return

    source = clean(d.get("source")) or "unknown"
    event = clean(d.get("event")) or "unknown"
    origin = clean(d.get("origin"))
    cwd = clean(d.get("cwd"))

    title = TITLES.get(source, source)                 # 第1行：应用名
    project = os.path.basename(cwd.rstrip("/")) if cwd else ""
    task = clean(d.get("message"))                      # 会话标题/状态（hook 生成，可能为空）
    subtitle = " · ".join(p for p in (project, task) if p) or "Session Completed"  # 第2行：项目名 · 会话标题
    if origin:                                          # 第3行：Local·本机 / Remote·host
        body = "%s · %s" % ("Local" if origin == LOCAL_HOST else "Remote", origin)
    else:
        body = ""

    log("received source=%s event=%s origin=%s cwd=%s message=%s"
        % (source, event, origin or "?", cwd or "?", subtitle))
    if os.path.isfile(SOUND):
        subprocess.Popen(["/usr/bin/afplay", SOUND],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.Popen(
        ["/usr/bin/osascript",
         "-e", "on run {t, s, b}",
         "-e", "display notification b with title t subtitle s",
         "-e", "end run", title, subtitle, body],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def shutdown(*_):
    try:
        os.remove(PID_FILE)
    except Exception:
        pass
    log("listener stopped")
    sys.exit(0)


signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind((HOST, PORT))
srv.listen(64)
log("listening on %s:%d" % (HOST, PORT))

while True:
    try:
        conn, _ = srv.accept()
    except OSError:
        continue
    payload = None
    try:
        conn.settimeout(2)
        data = b""
        while b"\n" not in data and len(data) < 65536:
            try:
                b = conn.recv(min(4096, 65536 - len(data)))
            except socket.timeout:
                break
            if not b:
                break
            data += b
        payload = data.split(b"\n", 1)[0]
    except Exception as e:
        log("error: %s" % e)
    finally:
        conn.close()
    if payload is not None:
        handle(payload.decode("utf-8", "replace"))
PY
