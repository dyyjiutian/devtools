#!/usr/bin/env bash
# Watch agent CLIs in the default tmux server and append a status suffix
# to each window name.
set -euo pipefail

SUFFIX_BUSY='+>'
SUFFIX_WAIT='+?'
SUFFIX_DONE='+v'
SUFFIX_FAIL='+x'

HISTORY_LINES=120

# Screen text of Claude Code 2.1, Codex 0.169, and Cursor Agent 2026.11.
# Columns: kind, match (has|starts), text. wait/busy only count on the visible
# screen; for fail/done/empty the lowest matching line in the history wins.
# When one line matches several rows, the earlier row wins.
SCREEN_MARKERS='wait	has	Do you want to proceed?
wait	has	Would you like to proceed?
wait	has	Do you want to make this edit
wait	has	Do you want to create
wait	has	Do you want to allow
wait	has	Would you like to run the following command?
wait	has	Would you like to make the following edits?
wait	has	Would you like to grant these permissions?
wait	has	Run this command?
wait	has	Waiting for approval
busy	has	esc to interrupt
busy	has	ctrl+c to stop
fail	starts	● API Error
fail	starts	⏺ API Error
fail	has	What should Claude do instead
fail	has	Resend your message
fail	starts	■
done	starts	●
done	starts	⏺
done	has	Worked for
done	has	Add a follow-up
empty	has	Claude Code v
empty	has	OpenAI Codex
empty	has	Plan, search, build anything'

INTERVAL=3
ONCE=0
FOREGROUND=0
INTERVAL_SET=0
COMMAND=""
SLEEP_PID=""

usage() {
  cat <<'EOF'
Usage: tmux-daemon.sh <start|stop|status> [options]

Watch the default tmux server and append a status suffix to window names
when the active pane is running Claude, Codex, or Cursor Agent.

Suffixes: +> running, +? waiting for confirmation, +v turn finished, +x turn failed.

Options:
  --interval N   Poll every N seconds (start only). Default: 3
  --once         Run one poll and exit (does not background, does not take the lock)
  -h, --help     Show this help
EOF
}

pid_file() {
  printf '%s\n' "${TMUX_DAEMON_PID_FILE:-${TMPDIR:-/tmp}/tmux-daemon.pid}"
}

interval_file() {
  printf '%s.interval\n' "$(pid_file)"
}

validate_interval() {
  case "${INTERVAL}" in
    ''|*[!0-9]*)
      echo "tmux-daemon: --interval must be a positive integer" >&2
      exit 1
      ;;
  esac
  if [[ "${INTERVAL}" -lt 1 ]]; then
    echo "tmux-daemon: --interval must be a positive integer" >&2
    exit 1
  fi
}

pid_alive() {
  local pid="${1:-}"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

read_pid() {
  local file
  file="$(pid_file)"
  [[ -f "${file}" ]] || return 1
  tr -d '[:space:]' <"${file}"
}

read_interval() {
  local file value
  file="$(interval_file)"
  if [[ -f "${file}" ]]; then
    value="$(tr -d '[:space:]' <"${file}")"
    case "${value}" in
      ''|*[!0-9]*) printf '%s\n' "3" ;;
      *) printf '%s\n' "${value}" ;;
    esac
    return 0
  fi
  printf '%s\n' "3"
}

window_base_name() {
  local name="$1"
  case "${name}" in
    *"${SUFFIX_BUSY}") printf '%s\n' "${name%"${SUFFIX_BUSY}"}" ;;
    *"${SUFFIX_WAIT}") printf '%s\n' "${name%"${SUFFIX_WAIT}"}" ;;
    *"${SUFFIX_DONE}") printf '%s\n' "${name%"${SUFFIX_DONE}"}" ;;
    *"${SUFFIX_FAIL}") printf '%s\n' "${name%"${SUFFIX_FAIL}"}" ;;
    *) printf '%s\n' "${name}" ;;
  esac
}

list_panes() {
  tmux list-panes -a -F '#{session_name}	#{window_id}	#{window_name}	#{pane_id}	#{pane_pid}	#{pane_active}	#{pane_height}' 2>/dev/null
}

# Appends the agent state of each pane's process tree to the pane rows:
# none, stopped (job-control stopped agent), or running.
annotate_panes() {
  local panes="$1" procs
  procs="$(ps -eo pid=,ppid=,stat=,comm=,args= 2>/dev/null)" || return 1
  printf '%s\n' "${procs}" | PANES="${panes}" awk '
    function base(path) {
      sub(/.*\//, "", path)
      return path
    }
    function is_agent(comm, args,   first) {
      comm = base(comm)
      first = args
      sub(/ .*/, "", first)
      first = base(first)
      if (comm ~ /^(claude|codex|cursor-agent)$/ || first ~ /^(claude|codex|cursor-agent)$/) {
        return 1
      }
      return (comm == "agent" || first == "agent") && args ~ /cursor/
    }
    NF >= 4 {
      args = $5
      for (i = 6; i <= NF; i++) {
        args = args " " $i
      }
      kids[$2] = kids[$2] " " $1
      stat[$1] = $3
      agent[$1] = is_agent($4, args)
    }
    END {
      n = split(ENVIRON["PANES"], rows, "\n")
      for (r = 1; r <= n; r++) {
        if (split(rows[r], f, "\t") < 7) {
          continue
        }
        state = "none"
        queue = f[5]
        while (queue != "" && state != "stopped") {
          m = split(queue, ids, " ")
          queue = ""
          for (j = 1; j <= m; j++) {
            pid = ids[j]
            if (seen[pid] == r) {
              continue
            }
            seen[pid] = r
            if (agent[pid]) {
              state = stat[pid] ~ /^T/ ? "stopped" : "running"
            }
            queue = queue kids[pid]
          }
        }
        print rows[r] "\t" state
      }
    }
  '
}

# Reads a pane tail on stdin and prints wait, busy, fail, done, empty, or unknown.
classify_screen() {
  local screen_rows="$1"
  MARKERS="${SCREEN_MARKERS}" awk -v rows="${screen_rows}" '
    function marker(s, transient,   i, is_transient) {
      for (i = 1; i <= n; i++) {
        is_transient = kind[i] == "wait" || kind[i] == "busy"
        if (is_transient != transient) {
          continue
        }
        if (how[i] == "starts" ? index(s, text[i]) == 1 : index(s, text[i]) > 0) {
          return kind[i]
        }
      }
      return ""
    }
    BEGIN {
      n = split(ENVIRON["MARKERS"], spec, "\n")
      for (i = 1; i <= n; i++) {
        split(spec[i], f, "\t")
        kind[i] = f[1]
        how[i] = f[2]
        text[i] = f[3]
      }
    }
    { line[NR] = $0 }
    END {
      top = NR - rows + 1
      for (i = (top < 1 ? 1 : top); i <= NR; i++) {
        k = marker(line[i], 1)
        if (k != "") {
          live[k] = 1
        }
      }
      if (live["wait"]) {
        print "wait"
        exit
      }
      if (live["busy"]) {
        print "busy"
        exit
      }
      best = "unknown"
      for (i = 1; i <= NR; i++) {
        k = marker(line[i], 0)
        if (k != "") {
          best = k
        }
      }
      print best
    }
  '
}

classify_pane() {
  local pane_id="$1" rows="$2" state="$3" text
  case "${state}" in
    none) printf 'clear\n'; return 0 ;;
    stopped) printf 'busy\n'; return 0 ;;
  esac
  if ! text="$(tmux capture-pane -p -S "-${HISTORY_LINES}" -t "${pane_id}" 2>/dev/null)"; then
    printf 'unknown\n'
    return 0
  fi
  printf '%s\n' "${text}" | classify_screen "${rows}"
}

desired_name() {
  local base="$1" kind="$2"
  case "${kind}" in
    busy) printf '%s%s\n' "${base}" "${SUFFIX_BUSY}" ;;
    wait) printf '%s%s\n' "${base}" "${SUFFIX_WAIT}" ;;
    done) printf '%s%s\n' "${base}" "${SUFFIX_DONE}" ;;
    fail) printf '%s%s\n' "${base}" "${SUFFIX_FAIL}" ;;
    clear|empty) printf '%s\n' "${base}" ;;
    *) return 1 ;;
  esac
}

apply_window_name() {
  local window_id="$1" current="$2" desired="$3"
  [[ "${current}" == "${desired}" ]] && return 0
  tmux rename-window -t "${window_id}" -- "${desired}" >/dev/null 2>&1 || true
}

tick() {
  local panes annotated session window_id window_name pane_id pane_pid active rows state
  local kind desired
  panes="$(list_panes)" || return 0
  annotated="$(annotate_panes "${panes}")" || return 0
  while IFS="$(printf '\t')" read -r session window_id window_name pane_id pane_pid active rows state; do
    [[ -n "${window_id}" && "${active}" == "1" ]] || continue
    kind="$(classify_pane "${pane_id}" "${rows}" "${state}")"
    desired="$(desired_name "$(window_base_name "${window_name}")" "${kind}")" || continue
    apply_window_name "${window_id}" "${window_name}" "${desired}"
  done <<EOF
${annotated}
EOF
}

clear_suffixes() {
  local panes session window_id window_name pane_id pane_pid active rows
  panes="$(list_panes)" || return 0
  while IFS="$(printf '\t')" read -r session window_id window_name pane_id pane_pid active rows; do
    [[ -n "${window_id}" && "${active}" == "1" ]] || continue
    apply_window_name "${window_id}" "${window_name}" "$(window_base_name "${window_name}")"
  done <<EOF
${panes}
EOF
}

cmd_status() {
  local pid interval
  interval="$(read_interval)"
  if pid="$(read_pid)" && pid_alive "${pid}"; then
    printf 'running\n'
    printf 'pid %s\n' "${pid}"
    printf 'interval %s\n' "${interval}"
    return 0
  fi
  printf 'stopped\n'
  printf 'interval %s\n' "${interval}"
}

cmd_stop() {
  local pid i
  if pid="$(read_pid)" && pid_alive "${pid}"; then
    kill -TERM "${pid}" 2>/dev/null || true
    i=0
    while pid_alive "${pid}"; do
      i=$((i + 1))
      if [[ "${i}" -gt 50 ]]; then
        echo "tmux-daemon: failed to stop pid ${pid}" >&2
        exit 1
      fi
      sleep 0.1
    done
  fi
  clear_suffixes
  rm -f "$(pid_file)" "$(interval_file)"
}

run_loop() {
  trap '' HUP
  trap '[[ -n "${SLEEP_PID}" ]] && kill "${SLEEP_PID}" 2>/dev/null; exit 0' TERM INT
  while true; do
    tick || true
    sleep "${INTERVAL}" &
    SLEEP_PID=$!
    wait "${SLEEP_PID}" || true
    SLEEP_PID=""
  done
}

cmd_start() {
  local self pid
  if [[ "${ONCE}" -eq 1 ]]; then
    tick
    return 0
  fi
  if [[ "${FOREGROUND}" -eq 1 ]]; then
    run_loop
  fi
  if pid="$(read_pid)" && pid_alive "${pid}"; then
    echo "tmux-daemon: already running (pid ${pid})" >&2
    exit 1
  fi
  self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  bash "${self}" start --interval "${INTERVAL}" --foreground </dev/null >/dev/null 2>&1 &
  printf '%s\n' "$!" >"$(pid_file)"
  printf '%s\n' "${INTERVAL}" >"$(interval_file)"
  printf 'tmux-daemon: started (pid %s, interval %ss)\n' "$!" "${INTERVAL}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --once)
      ONCE=1
      shift
      ;;
    --foreground)
      FOREGROUND=1
      shift
      ;;
    --interval)
      if [[ $# -lt 2 ]]; then
        echo "tmux-daemon: missing value for --interval" >&2
        exit 1
      fi
      INTERVAL="$2"
      INTERVAL_SET=1
      shift 2
      ;;
    start|stop|status)
      if [[ -n "${COMMAND}" ]]; then
        echo "tmux-daemon: only one command is allowed" >&2
        exit 1
      fi
      COMMAND="$1"
      shift
      ;;
    *)
      echo "tmux-daemon: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${COMMAND}" ]]; then
  usage >&2
  exit 1
fi

validate_interval
if [[ "${INTERVAL_SET}" -eq 1 && "${COMMAND}" != "start" ]]; then
  echo "tmux-daemon: --interval is only valid with start" >&2
  exit 1
fi

case "${COMMAND}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  status) cmd_status ;;
esac
