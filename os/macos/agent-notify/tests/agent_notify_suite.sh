#!/usr/bin/env bash
# Agent notify module suite — expects run_module_test.sh environment.
set -euo pipefail

SETUP_SH="$MODULE_ROOT/agent-hooks-setup.sh"
LISTENER_SH="$MODULE_ROOT/agent-listener.sh"
CAPTURE_SERVER_PID=""
LISTENER_PID=""

cleanup_background_processes() {
  if [[ -n "$CAPTURE_SERVER_PID" ]]; then
    kill "$CAPTURE_SERVER_PID" 2>/dev/null || true
  fi
  if [[ -n "$LISTENER_PID" ]]; then
    kill "$LISTENER_PID" 2>/dev/null || true
  fi
}
trap cleanup_background_processes EXIT

# Hooks already require python3. The hermetic profile PATH intentionally exposes
# only declared tools, so make that runtime dependency explicit for this suite.
ln -sf /usr/bin/python3 "$FAKE_BIN/python3"

render_function() {
  local function_name="$1"
  SETUP_NO_MAIN=1 /bin/bash -c '
    # shellcheck disable=SC1090
    source "$1"
    "$2"
  ' _ "$SETUP_SH" "$function_name"
}

test_help() {
  local out
  out="$(bash "$SETUP_SH" --help 2>&1)"
  assert_contains "$out" "claude|codex|cursor|all" "help lists every agent hook"
  pass "agent notify help ($DEVTOOLS_TEST_PROFILE)"
}

test_all_hooks_use_bounded_python_socket_sender() {
  local function_name hook
  for function_name in claude_hook_content codex_hook_content cursor_hook_content; do
    hook="$(render_function "$function_name")"
    assert_contains "$hook" "socket.create_connection" "$function_name uses Python socket"
    assert_contains "$hook" "sock.shutdown(socket.SHUT_WR)" "$function_name closes its write side"
    assert_not_contains "$hook" "nc -w" "$function_name must not depend on nc timeout semantics"
  done
  pass "all hooks use a bounded portable sender ($DEVTOOLS_TEST_PROFILE)"
}

start_capture_server() {
  local port_file="$1" payload_file="$2"
  /usr/bin/python3 - "$port_file" "$payload_file" <<'PY' &
import socket
import sys

port_file, payload_file = sys.argv[1:3]
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
    server.bind(("127.0.0.1", 0))
    server.listen(1)
    server.settimeout(3)
    with open(port_file, "w", encoding="utf-8") as fh:
        fh.write(str(server.getsockname()[1]))
    conn, _ = server.accept()
    with conn:
        conn.settimeout(1)
        data = b""
        while b"\n" not in data:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
        with open(payload_file, "wb") as fh:
            fh.write(data.split(b"\n", 1)[0])
        # A sender must close promptly after the one-line protocol payload.
        if conn.recv(1) != b"":
            raise SystemExit("unexpected bytes after the first payload line")
PY
  CAPTURE_SERVER_PID=$!
}

wait_for_file() {
  local path="$1" attempts=0
  while [[ ! -s "$path" && "$attempts" -lt 50 ]]; do
    sleep 0.02
    attempts=$((attempts + 1))
  done
  assert_file_exists "$path"
}

assert_payload_source() {
  local payload_file="$1" expected="$2"
  /usr/bin/python3 - "$payload_file" "$expected" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    payload = json.load(fh)
if payload.get("source") != sys.argv[2]:
    raise SystemExit("unexpected source: %r" % payload.get("source"))
PY
}

exercise_hook_sender() {
  local agent="$1" function_name="$2"
  local hook_file port_file payload_file port
  hook_file="$(mktemp "${TMPDIR:-/tmp}/agent-hook.XXXXXX")"
  port_file="$(mktemp "${TMPDIR:-/tmp}/agent-port.XXXXXX")"
  payload_file="$(mktemp "${TMPDIR:-/tmp}/agent-payload.XXXXXX")"
  rm -f "$port_file" "$payload_file"

  render_function "$function_name" >"$hook_file"
  chmod +x "$hook_file"
  start_capture_server "$port_file" "$payload_file"
  wait_for_file "$port_file"
  port="$(cat "$port_file")"

  case "$agent" in
    claude)
      printf '{"cwd":"/tmp/project"}\n' |
        CLIAGENT_HOOK_PORT="$port" bash "$hook_file" stop
      ;;
    codex)
      CLIAGENT_HOOK_PORT="$port" bash "$hook_file" \
        '{"type":"agent-turn-complete","cwd":"/tmp/project"}'
      ;;
    cursor)
      printf '{"workspace_roots":["/tmp/project"]}\n' |
        CLIAGENT_HOOK_PORT="$port" bash "$hook_file"
      ;;
  esac

  wait "$CAPTURE_SERVER_PID"
  CAPTURE_SERVER_PID=""
  assert_file_exists "$payload_file"
  assert_payload_source "$payload_file" "$agent"
  rm -f "$hook_file" "$port_file" "$payload_file"
}

test_hook_senders_close_without_waiting_for_server() {
  exercise_hook_sender claude claude_hook_content
  exercise_hook_sender codex codex_hook_content
  exercise_hook_sender cursor cursor_hook_content
  pass "hook senders close promptly for every agent ($DEVTOOLS_TEST_PROFILE)"
}

test_claude_hooks_have_framework_timeout() {
  local settings_program
  settings_program="$(render_function claude_settings_py)"
  /usr/bin/python3 - "$HOME/.claude/settings.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
base = str(Path.home() / ".cliagent-hook" / "hooks" / "cliagent-hook-claude.sh")
settings = {
    "hooks": {
        event: [{"hooks": [{"type": "command", "command": f"{base} {arg}"}]}]
        for event, arg in (("Stop", "stop"), ("Notification", "notification"))
    }
}
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(settings), encoding="utf-8")
PY
  printf '%s\n' "$settings_program" | python3 - add >/dev/null
  printf '%s\n' "$settings_program" | python3 - add >/dev/null

  /usr/bin/python3 - "$HOME/.claude/settings.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    settings = json.load(fh)
for event in ("Stop", "Notification"):
    managed = [
        hook
        for group in settings["hooks"][event]
        for hook in group.get("hooks", [])
        if "cliagent-hook-claude.sh" in hook.get("command", "")
    ]
    if len(managed) != 1:
        raise SystemExit("%s managed hook count is %d" % (event, len(managed)))
    if managed[0].get("timeout") != 10:
        raise SystemExit("%s timeout is %r" % (event, managed[0].get("timeout")))
PY
  pass "Claude hooks have an idempotent framework timeout ($DEVTOOLS_TEST_PROFILE)"
}

test_listener_closes_after_first_line() {
  local darwin_bin port pid_file log_file
  darwin_bin="$(mktemp -d "${TMPDIR:-/tmp}/agent-darwin-bin.XXXXXX")"
  printf '#!/usr/bin/env bash\nprintf "Darwin\\n"\n' >"$darwin_bin/uname"
  chmod +x "$darwin_bin/uname"
  port="$(/usr/bin/python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)"
  pid_file="$(mktemp "${TMPDIR:-/tmp}/agent-listener-pid.XXXXXX")"
  log_file="$(mktemp "${TMPDIR:-/tmp}/agent-listener-log.XXXXXX")"

  PATH="$darwin_bin:$PATH" \
    CLIAGENT_HOOK_PORT="$port" \
    CLIAGENT_HOOK_PID_FILE="$pid_file" \
    CLIAGENT_HOOK_LOG_FILE="$log_file" \
    bash "$LISTENER_SH" >/dev/null 2>&1 &
  LISTENER_PID=$!

  attempts=0
  while ! /usr/bin/python3 - "$port" <<'PY' 2>/dev/null; do
import socket
import sys
with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=0.1):
    pass
PY
    attempts=$((attempts + 1))
    if [[ "$attempts" -ge 50 ]]; then
      echo "FAIL: listener did not start" >&2
      kill "$LISTENER_PID" 2>/dev/null || true
      return 1
    fi
    sleep 0.02
  done

  /usr/bin/python3 - "$port" <<'PY'
import socket
import sys

payload = b'{"source":"claude","event":"stop","origin":"remote","cwd":"/tmp/project","message":""}\n'
with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=1) as sock:
    sock.settimeout(0.75)
    sock.sendall(payload)
    if sock.recv(1) != b"":
        raise SystemExit("listener sent unexpected response bytes")
PY

  kill "$LISTENER_PID" 2>/dev/null || true
  wait "$LISTENER_PID" 2>/dev/null || true
  LISTENER_PID=""
  rm -rf "$darwin_bin"
  rm -f "$pid_file" "$log_file"
  pass "listener closes immediately after one protocol line ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_all_hooks_use_bounded_python_socket_sender
test_hook_senders_close_without_waiting_for_server
test_claude_hooks_have_framework_timeout
test_listener_closes_after_first_line
