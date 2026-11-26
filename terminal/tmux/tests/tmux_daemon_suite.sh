#!/usr/bin/env bash
# tmux-daemon suite — expects run_module_test.sh environment.
set -euo pipefail

DAEMON="$MODULE_ROOT/tmux-daemon.sh"
TMUX_CONF="$MODULE_ROOT/tmux.conf"

# Screen tails captured from Claude Code 2.1, Codex 0.169, and Cursor Agent 2026.11.
CLAUDE_FRESH=$' ▐▛███▛█   Claude Code v2.1.332\n▝▜██████▀  model · API Usage Billing\n\n────────\n❯ Try "how does <filepath> work?"\n────────\n  ⏵⏵ bypass permissions on (shift+tab to cycle)'
CLAUDE_BUSY=$'❯ fix the login bug\n\n● Reading src/login.ts\n\n✻ Thinking… (12s · esc to interrupt)\n────────\n❯ \n────────'
CLAUDE_CONFIRM=$'● Bash(rm -rf build)\n\n Do you want to proceed?\n ❯ 1. Yes\n   2. No, and tell Claude what to do differently (esc)'
CLAUDE_FAILED=$'❯ Run the shell command sleep 8\n\n● API Error: Request rejected (429) · quota exhausted\n\n────────\n❯ Resend your message to try again\n────────'
CLAUDE_DONE_AFTER_ERROR=$'● API Error: Request rejected (429)\n\n❯ try again\n\n● ok\n\n────────\n❯ \n────────'
CODEX_FRESH=$'  >_ OpenAI Codex (v0.169.0)\n     /tmp/work\n\n› Ask Codex to do anything\n\n  ← for agents · ? for shortcuts'
CODEX_BUSY=$'› Run the shell command sleep 8\n\n• Working (6s • esc to interrupt)\n\n› Ask Codex to do anything\n\n  ← for agents · ? for shortcuts'
CODEX_CONFIRM=$'• Running touch b.txt\n\n  Would you like to run the following command?\n\n  $ touch b.txt\n\n› 1. Yes, proceed (y)\n  3. No, and tell Codex what to do differently (esc)\n\n  Press enter to confirm or esc to cancel'
CODEX_DONE=$'› Reply with exactly: ok2\n\n• ok2\n\n  Worked for 5s • 11:14 PM\n\n› Ask Codex to do anything\n\n  ← for agents · ? for shortcuts'
CODEX_INTERRUPTED=$'✗ You canceled the request to run touch b.txt\n\n■ Conversation interrupted - use /feedback if something went wrong\n\n› Ask Codex to do anything\n\n  ← for agents · ? for shortcuts'
CURSOR_FRESH=$'  Cursor Agent\n  v2026.11.22\n\n  → Plan, search, build anything\n\n  Claude Opus 5.5 300K High                     Run Everything'
CURSOR_BUSY=$'  Run the shell command `sleep 8`\n\n ⠠⠛ Working  1 token\n\n  → Add a follow-up                            ctrl+c to stop\n\n  Claude Opus 5.5 300K High                     Run Everything'
CURSOR_CONFIRM=$'  $ rm -rf build\n  Run this command?\n  → Run (once) (y)\n    Skip (esc or n)\n\n  → Add a follow-up                            ctrl+c to stop'
CURSOR_DONE=$'  $ sleep 8 9.7s\n\n  ok\n\n  → Add a follow-up\n\n  Claude Opus 5.5 300K High · 6.8%              Run Everything'

# The fake server keeps one row per pane in panes.tsv with the columns the
# daemon asks list-panes for: window_id, pane_id, pane_pid, pane_active,
# pane_height, and @agent_state ("-" when unset).
install_fakes() {
  cat >"$FAKE_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
fx="${TMUX_DAEMON_FIXTURE:?}"
cmd="${1:-}"
shift || true
case "${cmd}" in
  list-panes)
    if [[ ! -f "${fx}/panes.tsv" ]]; then
      echo "no server" >&2
      exit 1
    fi
    cat "${fx}/panes.tsv"
    ;;
  capture-pane)
    target=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t)
          target="${2:-}"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    [[ -n "${target}" && -f "${fx}/capture/${target}" ]] || exit 1
    cat "${fx}/capture/${target}"
    ;;
  set-option)
    target=""
    unset_opt=0
    words=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t)
          target="${2:-}"
          shift 2
          ;;
        -*)
          case "$1" in *u*) unset_opt=1 ;; esac
          shift
          ;;
        *)
          words+=("$1")
          shift
          ;;
      esac
    done
    [[ "${words[0]:-}" == "@agent_state" ]] || exit 1
    value="${words[1]:--}"
    [[ "${unset_opt}" -eq 1 ]] && value="-"
    if [[ -f "${fx}/fail-set" ]] && grep -qx "${target}" "${fx}/fail-set"; then
      echo "set-option failed" >&2
      exit 1
    fi
    printf '%s\t%s\n' "${target}" "${value}" >>"${fx}/states.tsv"
    awk -F '\t' -v id="${target}" -v value="${value}" '
      BEGIN { OFS = "\t" }
      $1 == id { $6 = value }
      { print }
    ' "${fx}/panes.tsv" >"${fx}/panes.tsv.new"
    mv "${fx}/panes.tsv.new" "${fx}/panes.tsv"
    ;;
  *)
    printf '%s %s\n' "${cmd}" "$*" >>"${fx}/unexpected.log"
    exit 1
    ;;
esac
EOF
  cat >"$FAKE_BIN/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -z "${TMUX_DAEMON_PS_FILE:-}" || ! -f "${TMUX_DAEMON_PS_FILE}" ]]; then
  exit 1
fi
cat "${TMUX_DAEMON_PS_FILE}"
EOF
  chmod +x "$FAKE_BIN/tmux" "$FAKE_BIN/ps"
}

new_fx() {
  FX="$HOME/tmux-daemon-fx"
  rm -rf "$FX"
  mkdir -p "$FX/capture"
  : >"$FX/states.tsv"
  export TMUX_DAEMON_FIXTURE="$FX"
  export TMUX_DAEMON_PID_FILE="$FX/pid"
  export TMUX_DAEMON_PS_FILE="$FX/ps.tsv"
}

add_pane() {
  local window_id="$1" pane_id="$2" pane_pid="$3" state="${4:--}" rows="${5:-40}"
  printf '%s\t%s\t%s\t1\t%s\t%s\n' \
    "${window_id}" "${pane_id}" "${pane_pid}" "${rows}" "${state}" >>"$FX/panes.tsv"
}

set_capture() {
  local pane_id="$1" text="$2"
  printf '%s\n' "${text}" >"$FX/capture/${pane_id}"
}

set_ps() {
  printf '%s\n' "$1" >"$FX/ps.tsv"
}

run_once() {
  bash "$DAEMON" start --once
}

window_state() {
  awk -F '\t' -v id="$1" '$1 == id { print $6 }' "$FX/panes.tsv"
}

set_count() {
  awk -F '\t' -v id="$1" '$1 == id { n++ } END { print n + 0 }' "$FX/states.tsv"
}

assert_no_other_tmux_calls() {
  if [[ -s "$FX/unexpected.log" ]]; then
    echo "FAIL: unexpected tmux calls:" >&2
    cat "$FX/unexpected.log" >&2
    return 1
  fi
}

# Prints the window state after one poll of a single agent pane.
classify_fixture() {
  local text="$1" start_state="${2:--}" rows="${3:-40}"
  new_fx
  add_pane @1 %1 10 "${start_state}" "${rows}"
  set_capture %1 "${text}"
  set_ps $'10 1 S claude claude'
  run_once
  assert_no_other_tmux_calls
  window_state @1
}

install_fakes

test_help() {
  local out
  out="$(bash "$DAEMON" --help 2>&1)"
  assert_contains "$out" "--interval" "help mentions --interval"
  assert_contains "$out" "--once" "help mentions --once"
  assert_contains "$out" "start" "help mentions start"
  assert_contains "$out" "stop" "help mentions stop"
  assert_contains "$out" "status" "help mentions status"
  assert_contains "$out" "@agent_state" "help names the window option"
  pass "tmux-daemon --help ($DEVTOOLS_TEST_PROFILE)"
}

test_unknown_flag() {
  local rc=0
  bash "$DAEMON" --not-a-real-flag >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "unknown flag should exit 1"
  pass "tmux-daemon unknown flag ($DEVTOOLS_TEST_PROFILE)"
}

test_busy_state() {
  local out
  new_fx
  add_pane @1 %1 10
  set_capture %1 "${CLAUDE_BUSY}"$'\nSECRET_PANE_BODY'
  set_ps $'1 0 Ss bash bash\n10 1 S claude claude'
  out="$(run_once 2>&1)"
  assert_not_contains "$out" "SECRET_PANE_BODY" "pane body is not printed"
  assert_eq "$(window_state @1)" "busy" "busy claude sets busy"
  assert_no_other_tmux_calls
  pass "tmux-daemon busy state ($DEVTOOLS_TEST_PROFILE)"
}

test_silence_stays_busy() {
  new_fx
  add_pane @1 %1 10 busy
  set_capture %1 "${CODEX_BUSY}"
  set_ps $'10 1 S codex codex'
  run_once
  assert_eq "$(set_count @1)" "0" "unchanged state is not rewritten"
  assert_eq "$(window_state @1)" "busy" "state stays busy"
  pass "tmux-daemon silence stays busy ($DEVTOOLS_TEST_PROFILE)"
}

test_real_screens() {
  assert_eq "$(classify_fixture "${CLAUDE_FRESH}")" "-" "fresh Claude has no state"
  assert_eq "$(classify_fixture "${CLAUDE_BUSY}")" "busy" "busy Claude"
  assert_eq "$(classify_fixture "${CLAUDE_CONFIRM}")" "wait" "Claude permission prompt"
  assert_eq "$(classify_fixture "${CLAUDE_FAILED}")" "fail" "Claude API error"
  assert_eq "$(classify_fixture "${CLAUDE_DONE_AFTER_ERROR}")" "done" "Claude turn after an old error"
  assert_eq "$(classify_fixture "${CODEX_FRESH}")" "-" "fresh Codex has no state"
  assert_eq "$(classify_fixture "${CODEX_BUSY}")" "busy" "busy Codex"
  assert_eq "$(classify_fixture "${CODEX_CONFIRM}")" "wait" "Codex approval prompt"
  assert_eq "$(classify_fixture "${CODEX_DONE}")" "done" "finished Codex turn"
  assert_eq "$(classify_fixture "${CODEX_INTERRUPTED}")" "fail" "interrupted Codex turn"
  assert_eq "$(classify_fixture "${CURSOR_FRESH}")" "-" "fresh Cursor Agent has no state"
  assert_eq "$(classify_fixture "${CURSOR_BUSY}")" "busy" "busy Cursor Agent"
  assert_eq "$(classify_fixture "${CURSOR_CONFIRM}")" "wait" "Cursor Agent approval prompt"
  assert_eq "$(classify_fixture "${CURSOR_DONE}")" "done" "finished Cursor Agent turn"
  pass "tmux-daemon real CLI screens ($DEVTOOLS_TEST_PROFILE)"
}

test_confirm_beats_busy() {
  assert_eq "$(classify_fixture "${CLAUDE_BUSY}"$'\n'"${CLAUDE_CONFIRM}")" "wait" "confirmation beats busy"
  pass "tmux-daemon confirmation ($DEVTOOLS_TEST_PROFILE)"
}

test_busy_beats_old_error() {
  assert_eq "$(classify_fixture "${CLAUDE_FAILED}"$'\n'"${CLAUDE_BUSY}")" "busy" "old error does not beat a running turn"
  pass "tmux-daemon busy beats old error ($DEVTOOLS_TEST_PROFILE)"
}

test_stale_status_above_screen() {
  assert_eq "$(classify_fixture "${CODEX_BUSY}"$'\n'"${CODEX_DONE}" busy 9)" "done" \
    "a busy line scrolled above the screen is ignored"
  pass "tmux-daemon stale status above screen ($DEVTOOLS_TEST_PROFILE)"
}

test_new_session_header_wins() {
  assert_eq "$(classify_fixture "${CLAUDE_DONE_AFTER_ERROR}"$'\n'"${CODEX_FRESH}" done)" "-" \
    "a fresh session below an old turn has no state"
  pass "tmux-daemon new session header ($DEVTOOLS_TEST_PROFILE)"
}

test_stopped_agent_in_tree() {
  new_fx
  add_pane @1 %1 1
  set_capture %1 "${CLAUDE_FRESH}"
  set_ps $'1 0 Ss bash bash\n10 1 T claude claude'
  run_once
  assert_eq "$(window_state @1)" "busy" "stopped agent under the shell stays busy"
  pass "tmux-daemon stopped agent ($DEVTOOLS_TEST_PROFILE)"
}

test_no_agent_clears_state() {
  new_fx
  add_pane @1 %1 1 done
  set_capture %1 "shell prompt"
  set_ps $'1 0 Ss bash bash'
  run_once
  assert_eq "$(window_state @1)" "-" "state is unset when the agent is gone"
  assert_eq "$(set_count @1)" "1" "state is unset once"
  pass "tmux-daemon clear when agent exits ($DEVTOOLS_TEST_PROFILE)"
}

test_non_agents_are_ignored() {
  new_fx
  add_pane @1 %1 7
  add_pane @2 %2 8
  add_pane @3 %3 9
  set_capture %1 "${CODEX_BUSY}"
  set_capture %2 "${CODEX_BUSY}"
  set_capture %3 "${CODEX_BUSY}"
  set_ps $'7 1 S make make test\n8 1 S tail tail -f claude.log\n9 1 S agent agent'
  run_once
  assert_eq "$(set_count @1)" "0" "make is not marked"
  assert_eq "$(set_count @2)" "0" "tail is not marked"
  assert_eq "$(set_count @3)" "0" "plain agent is not marked"
  pass "tmux-daemon ignores non-agents ($DEVTOOLS_TEST_PROFILE)"
}

test_real_process_shapes() {
  local shape
  while IFS= read -r shape; do
    new_fx
    add_pane @1 %1 1
    set_capture %1 "${CURSOR_BUSY}"
    set_ps "1 0 Ss bash -bash"$'\n'"${shape}"
    run_once
    assert_eq "$(window_state @1)" "busy" "agent process is marked: ${shape}"
  done <<'EOF'
6 1 S agent agent /opt/cursor-agent/bin/agent
6 1 S cursor-agent cursor-agent
6 1 Sl+ MainThread /home/u/.local/bin/cursor-agent --use-system-ca /home/u/.local/share/cursor-agent/versions/1/index.js
6 1 Sl+ MainThread /home/u/.local/bin/agent --use-system-ca /home/u/.local/share/cursor-agent/versions/1/index.js
6 1 Sl+ /Users/u/.local/bin/claude claude
6 1 Sl+ codex /usr/lib/node_modules/@openai/codex/vendor/x86_64-unknown-linux-musl/bin/codex
EOF
  pass "tmux-daemon real process shapes ($DEVTOOLS_TEST_PROFILE)"
}

test_unknown_screen() {
  assert_eq "$(classify_fixture "hello")" "-" "first unknown screen sets no state"
  assert_eq "$(set_count @1)" "0" "first unknown screen is not written"
  assert_eq "$(classify_fixture "hello" busy)" "busy" "unknown screen keeps the previous state"
  assert_eq "$(set_count @1)" "0" "unknown screen is not written"
  pass "tmux-daemon unknown screen ($DEVTOOLS_TEST_PROFILE)"
}

test_idempotent() {
  new_fx
  add_pane @1 %1 10
  set_capture %1 "${CLAUDE_BUSY}"
  set_ps $'10 1 S claude claude'
  run_once
  run_once
  assert_eq "$(window_state @1)" "busy" "second poll keeps busy"
  assert_eq "$(set_count @1)" "1" "second poll does not write again"
  assert_no_other_tmux_calls
  pass "tmux-daemon idempotent poll ($DEVTOOLS_TEST_PROFILE)"
}

test_set_failure_skips_one_window() {
  new_fx
  add_pane @1 %1 10
  add_pane @2 %2 11
  set_capture %1 "${CLAUDE_BUSY}"
  set_capture %2 "${CODEX_BUSY}"
  set_ps $'10 1 S claude claude\n11 1 S codex codex'
  printf '@2\n' >"$FX/fail-set"
  run_once
  assert_eq "$(window_state @1)" "busy" "the other window is still marked"
  assert_eq "$(window_state @2)" "-" "failed window is skipped"
  pass "tmux-daemon set failure is isolated ($DEVTOOLS_TEST_PROFILE)"
}

test_second_start_exits() {
  local rc=0 out sleeper
  new_fx
  sleep 30 &
  sleeper=$!
  disown "$sleeper" 2>/dev/null || true
  printf '%s\n' "$sleeper" >"$FX/pid"
  out="$(bash "$DAEMON" start 2>&1)" || rc=$?
  kill "$sleeper" 2>/dev/null || true
  wait "$sleeper" 2>/dev/null || true
  assert_eq "$rc" "1" "second start exits 1"
  assert_contains "$out" "already running" "second start explains the lock"
  pass "tmux-daemon single instance ($DEVTOOLS_TEST_PROFILE)"
}

test_stop_clears_states() {
  local sleeper
  new_fx
  add_pane @1 %1 10 busy
  add_pane @2 %2 11 done
  add_pane @3 %3 12
  set_ps $'10 1 S claude claude\n11 1 S codex codex\n12 1 S bash bash'
  sleep 30 &
  sleeper=$!
  disown "$sleeper" 2>/dev/null || true
  printf '%s\n' "$sleeper" >"$FX/pid"
  bash "$DAEMON" stop
  if kill -0 "$sleeper" 2>/dev/null; then
    kill "$sleeper" 2>/dev/null || true
    echo "FAIL: stop left the daemon pid alive" >&2
    return 1
  fi
  assert_eq "$(window_state @1)" "-" "stop clears busy"
  assert_eq "$(window_state @2)" "-" "stop clears done"
  assert_eq "$(set_count @3)" "0" "stop leaves a window without state alone"
  assert_no_other_tmux_calls
  pass "tmux-daemon stop clears states ($DEVTOOLS_TEST_PROFILE)"
}

wait_for() {
  local tries=0
  until "$@"; do
    tries=$((tries + 1))
    if [[ "${tries}" -gt 50 ]]; then
      return 1
    fi
    sleep 0.1
  done
}

state_is() {
  [[ "$(window_state "$1")" == "$2" ]]
}

test_background_daemon_lifecycle() {
  local out pid started ended
  new_fx
  add_pane @1 %1 10
  set_capture %1 "${CODEX_BUSY}"
  set_ps $'10 1 S codex codex'
  bash "$DAEMON" start --interval 30 </dev/null >/dev/null 2>&1
  pid="$(cat "$FX/pid")"
  assert_contains "$(bash "$DAEMON" status)" "running" "status sees the daemon right after start"
  if ! wait_for state_is @1 busy; then
    kill "${pid}" 2>/dev/null || true
    echo "FAIL: background daemon did not run its first poll" >&2
    return 1
  fi
  out="$(bash "$DAEMON" status)"
  assert_contains "$out" "pid ${pid}" "status prints the daemon pid"
  assert_contains "$out" "interval 30" "status prints --interval 30"
  started="$(date +%s)"
  bash "$DAEMON" stop
  ended="$(date +%s)"
  if kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}" 2>/dev/null || true
    echo "FAIL: stop left the background daemon alive" >&2
    return 1
  fi
  if [[ $((ended - started)) -gt 3 ]]; then
    echo "FAIL: stop waited for the poll interval instead of interrupting it" >&2
    return 1
  fi
  assert_eq "$(window_state @1)" "-" "stop clears the state written by the daemon"
  assert_contains "$(bash "$DAEMON" status)" "stopped" "status reports stopped after stop"
  pass "tmux-daemon background lifecycle ($DEVTOOLS_TEST_PROFILE)"
}

test_interval_and_missing_tmux() {
  local out rc=0
  new_fx
  out="$(bash "$DAEMON" status 2>&1)"
  assert_contains "$out" "stopped" "status reports stopped"
  assert_contains "$out" "interval 3" "default interval is 3"
  rm -f "$FX/panes.tsv"
  bash "$DAEMON" start --once
  rc=0
  bash "$DAEMON" start --interval 0 --once >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "interval 0 is rejected"
  pass "tmux-daemon interval and missing tmux ($DEVTOOLS_TEST_PROFILE)"
}

test_tmux_conf_draws_every_state() {
  local conf state
  conf="$(cat "$TMUX_CONF")"
  for state in busy wait done fail; do
    assert_contains "$conf" "#{==:#{@agent_state},${state}}" "tmux.conf draws ${state}"
  done
  assert_contains "$(grep '^set -g window-status-format' "$TMUX_CONF")" "#{E:@agent-status}" \
    "window list shows the agent status"
  assert_contains "$(grep '^set -g window-status-current-format' "$TMUX_CONF")" "#{E:@agent-status}" \
    "current window shows the agent status"
  pass "tmux-daemon tmux.conf status format ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_unknown_flag
test_busy_state
test_silence_stays_busy
test_real_screens
test_confirm_beats_busy
test_busy_beats_old_error
test_stale_status_above_screen
test_new_session_header_wins
test_stopped_agent_in_tree
test_no_agent_clears_state
test_non_agents_are_ignored
test_real_process_shapes
test_unknown_screen
test_idempotent
test_set_failure_skips_one_window
test_second_start_exits
test_stop_clears_states
test_background_daemon_lifecycle
test_interval_and_missing_tmux
test_tmux_conf_draws_every_state

echo "PASS: tmux-daemon suite complete ($DEVTOOLS_TEST_PROFILE)"
