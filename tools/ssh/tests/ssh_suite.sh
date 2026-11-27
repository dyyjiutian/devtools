#!/usr/bin/env bash
# SSH / fssh module suite — expects run_module_test.sh environment.
set -euo pipefail

FSSH_SH="$MODULE_ROOT/fssh.sh"
SETUP_SH="$MODULE_ROOT/setup.sh"

write_hosts_config() {
  mkdir -p "$HOME/.ssh"
  cat >"$HOME/.ssh/config" <<'EOF'
Host foo-dev
    HostName 10.0.0.1

Host bar-dev
    HostName 10.0.0.2

Host prod
    HostName 10.0.0.3

Host DevBox
    HostName 10.0.0.4

Host jump-*
    HostName 10.0.0.5
EOF
}

# Main config plus a single-file Include (relative to ~/.ssh).
write_hosts_config_with_include() {
  mkdir -p "$HOME/.ssh/config.d"
  cat >"$HOME/.ssh/config" <<'EOF'
Include config.d/work

Host foo-dev
    HostName 10.0.0.1

Host jump-*
    HostName 10.0.0.5
EOF
  cat >"$HOME/.ssh/config.d/work" <<'EOF'
Host work-box
    HostName 10.0.0.9

Host work-jump-*
    HostName 10.0.0.8
EOF
}

# ~50 concrete Host aliases across main + Include, with typical directive lines
# (enough total lines to catch per-line external-process regressions).
write_hosts_config_perf50() {
  local i
  mkdir -p "$HOME/.ssh/config.d"
  {
    echo "# perf fixture: main + Include"
    echo "Include config.d/extra"
    echo ""
    for ((i = 1; i <= 40; i++)); do
      printf 'Host host-%02d\n' "$i"
      printf '    HostName 10.0.0.%d\n' "$i"
      echo "    User deploy"
      echo "    Port 22"
      echo ""
    done
    echo "Host jump-*"
    echo "    HostName 10.0.0.254"
  } >"$HOME/.ssh/config"
  {
    echo "# perf fixture: included hosts"
    for ((i = 41; i <= 50; i++)); do
      printf 'Host host-%02d\n' "$i"
      printf '    HostName 10.0.1.%d\n' "$i"
      echo "    User deploy"
      echo "    Port 22"
      echo ""
    done
  } >"$HOME/.ssh/config.d/extra"
}

# Source fssh helpers without running the interactive main path.
run_fssh_fn() {
  FSSH_NO_MAIN=1 /bin/bash -c '
    set -euo pipefail
    # shellcheck disable=SC1090
    source "$1"
    shift
    "$@"
  ' _ "$FSSH_SH" "$@"
}

test_setup_help() {
  local out
  out="$(bash "$SETUP_SH" --help 2>&1)"
  assert_contains "$out" "dry-run" "setup --help mentions dry-run"
  pass "ssh setup --help ($DEVTOOLS_TEST_PROFILE)"
}

test_fssh_help_mentions_query() {
  local out
  out="$(bash "$FSSH_SH" --help 2>&1)"
  assert_contains "$out" "query" "fssh help mentions query matching"
  assert_contains "$out" "substring" "fssh help mentions substring matching"
  assert_contains "$out" "-t, --tmux" "fssh help mentions -t/--tmux session flag"
  assert_contains "$out" "-n, --no-tmux" "fssh help mentions -n/--no-tmux"
  pass "fssh --help mentions fuzzy query ($DEVTOOLS_TEST_PROFILE)"
}

test_list_hosts_follows_include() {
  write_hosts_config_with_include
  local out
  out="$(run_fssh_fn list_hosts)"
  assert_contains "$out" "foo-dev" "lists Host from main config"
  assert_contains "$out" "work-box" "lists Host from Include file"
  assert_not_contains "$out" "jump-*" "excludes main-config wildcards"
  assert_not_contains "$out" "work-jump-*" "excludes Include wildcards"
  pass "fssh list_hosts follows Include ($DEVTOOLS_TEST_PROFILE)"
}

test_list_hosts_follows_tilde_include() {
  mkdir -p "$HOME/.ssh/config.d"
  cat >"$HOME/.ssh/config" <<'EOF'
Include ~/.ssh/config.d/extra

Host main-host
    HostName 10.0.0.1
EOF
  cat >"$HOME/.ssh/config.d/extra" <<'EOF'
Host from-tilde
    HostName 10.0.0.2
EOF
  local out
  out="$(run_fssh_fn list_hosts)"
  assert_contains "$out" "main-host" "lists Host from main config"
  assert_contains "$out" "from-tilde" "lists Host from tilde Include path"
  pass "fssh list_hosts follows tilde Include ($DEVTOOLS_TEST_PROFILE)"
}

test_match_hosts_from_include() {
  write_hosts_config_with_include
  local out
  out="$(run_fssh_fn match_hosts work)"
  assert_eq "$out" "work-box" "query matches Host from Include file"
  pass "fssh match_hosts from Include ($DEVTOOLS_TEST_PROFILE)"
}

test_match_hosts_exact() {
  write_hosts_config
  local out
  out="$(run_fssh_fn match_hosts DevBox)"
  assert_eq "$out" "DevBox" "exact match is case-insensitive unique"
  pass "fssh match_hosts exact ($DEVTOOLS_TEST_PROFILE)"
}

test_match_hosts_exact_beats_substring() {
  write_hosts_config
  # Add an alias that is also a substring of others would not apply;
  # exact "prod" must not also return foo-dev style noise — only prod.
  local out
  out="$(run_fssh_fn match_hosts prod)"
  assert_eq "$out" "prod" "exact match returns only the exact host"
  pass "fssh match_hosts exact beats substring ($DEVTOOLS_TEST_PROFILE)"
}

test_match_hosts_substring_unique() {
  write_hosts_config
  # Query that hits only DevBox via substring (case-insensitive).
  local out
  out="$(run_fssh_fn match_hosts devbox)"
  assert_eq "$out" "DevBox" "case-insensitive substring unique match"
  pass "fssh match_hosts unique substring ($DEVTOOLS_TEST_PROFILE)"
}

test_match_hosts_substring_multiple() {
  write_hosts_config
  local out
  out="$(run_fssh_fn match_hosts dev)"
  assert_contains "$out" "foo-dev" "substring includes foo-dev"
  assert_contains "$out" "bar-dev" "substring includes bar-dev"
  assert_contains "$out" "DevBox" "substring includes DevBox"
  assert_not_contains "$out" "prod" "substring excludes prod"
  local count
  count="$(printf '%s\n' "$out" | grep -c . || true)"
  assert_eq "$count" "3" "substring returns exactly three matches"
  pass "fssh match_hosts multiple substring ($DEVTOOLS_TEST_PROFILE)"
}

test_match_hosts_ignores_wildcards() {
  write_hosts_config
  local out
  out="$(run_fssh_fn match_hosts jump || true)"
  assert_eq "$out" "" "wildcard Host entries are excluded"
  pass "fssh match_hosts ignores wildcards ($DEVTOOLS_TEST_PROFILE)"
}

test_resolve_host_unique() {
  write_hosts_config
  local out
  out="$(run_fssh_fn resolve_host foo)"
  assert_eq "$out" "foo-dev" "unique substring resolves without fzf"
  pass "fssh resolve_host unique ($DEVTOOLS_TEST_PROFILE)"
}

test_resolve_host_none() {
  write_hosts_config
  local rc=0 out
  out="$(run_fssh_fn resolve_host nope 2>&1)" || rc=$?
  assert_eq "$rc" "1" "no match exits 1"
  assert_contains "$out" "No SSH host matching" "error mentions no match"
  pass "fssh resolve_host none ($DEVTOOLS_TEST_PROFILE)"
}

test_resolve_host_multiple_uses_fzf() {
  write_hosts_config
  mkdir -p "$FAKE_BIN"
  # fzf reads candidates on stdin; pick a deterministic host.
  cat >"$FAKE_BIN/fzf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
grep -x 'bar-dev'
EOF
  chmod +x "$FAKE_BIN/fzf"
  # ssh may be invoked by preview; never call it in this path if fzf is non-interactive.
  # Still provide a stub in case preview runs.
  if [[ ! -x "$FAKE_BIN/ssh" ]]; then
    cat >"$FAKE_BIN/ssh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$FAKE_BIN/ssh"
  fi

  local out
  out="$(PATH="$FAKE_BIN:$PATH" run_fssh_fn resolve_host dev)"
  assert_eq "$out" "bar-dev" "multiple matches go through fzf"
  pass "fssh resolve_host multiple via fzf ($DEVTOOLS_TEST_PROFILE)"
}

test_match_sessions_exact() {
  local out
  out="$(run_fssh_fn match_sessions Main $'Main\nwork\nMainLab')"
  assert_eq "$out" "Main" "exact case-insensitive session wins"
  pass "fssh match_sessions exact ($DEVTOOLS_TEST_PROFILE)"
}

test_match_sessions_exact_beats_substring() {
  local out
  out="$(run_fssh_fn match_sessions main $'main\nmain-extra\nwork')"
  assert_eq "$out" "main" "exact match beats substring siblings"
  pass "fssh match_sessions exact beats substring ($DEVTOOLS_TEST_PROFILE)"
}

test_match_sessions_substring_unique() {
  local out
  out="$(run_fssh_fn match_sessions wor $'main\nwork\ndev')"
  assert_eq "$out" "work" "unique substring matches one session"
  pass "fssh match_sessions unique substring ($DEVTOOLS_TEST_PROFILE)"
}

test_match_sessions_substring_multiple() {
  local out count
  out="$(run_fssh_fn match_sessions a $'main\nwork\ndata')"
  count="$(printf '%s\n' "$out" | grep -c . || true)"
  assert_eq "$count" "2" "substring returns two session matches"
  assert_contains "$out" "main" "includes main"
  assert_contains "$out" "data" "includes data"
  pass "fssh match_sessions multiple substring ($DEVTOOLS_TEST_PROFILE)"
}

test_resolve_session_unique() {
  local out
  out="$(run_fssh_fn resolve_session mai $'main\nwork')"
  assert_eq "$out" "main" "unique substring resolves without fzf"
  pass "fssh resolve_session unique ($DEVTOOLS_TEST_PROFILE)"
}

test_resolve_session_none() {
  local rc=0 out
  out="$(run_fssh_fn resolve_session nope $'main\nwork' 2>&1)" || rc=$?
  assert_eq "$rc" "1" "no match exits 1"
  assert_contains "$out" "No tmux session matching" "error mentions no match"
  pass "fssh resolve_session none ($DEVTOOLS_TEST_PROFILE)"
}

test_resolve_session_multiple_uses_fzf() {
  mkdir -p "$FAKE_BIN"
  cat >"$FAKE_BIN/fzf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
grep -x 'main'
EOF
  chmod +x "$FAKE_BIN/fzf"

  local out
  out="$(PATH="$FAKE_BIN:$PATH" run_fssh_fn resolve_session a $'main\nwork\ndata')"
  assert_eq "$out" "main" "multiple session matches go through fzf"
  pass "fssh resolve_session multiple via fzf ($DEVTOOLS_TEST_PROFILE)"
}

test_fssh_tmux_requires_host() {
  local rc=0 out
  out="$(bash "$FSSH_SH" -t main 2>&1)" || rc=$?
  assert_eq "$rc" "1" "-t without host exits 1"
  assert_contains "$out" "-t/--tmux requires a host" "error says host is required"
  pass "fssh -t requires host ($DEVTOOLS_TEST_PROFILE)"
}

test_fssh_tmux_conflicts_with_no_tmux() {
  local rc=0 out
  out="$(bash "$FSSH_SH" prod -t main -n 2>&1)" || rc=$?
  assert_eq "$rc" "1" "-t with -n exits 1"
  assert_contains "$out" "mutually exclusive" "error mentions mutual exclusion"
  pass "fssh -t conflicts with -n ($DEVTOOLS_TEST_PROFILE)"
}

test_session_menu_order_with_sessions() {
  local out
  out="$(run_fssh_fn session_menu_entries $'main\nwork')"
  assert_eq "$(printf '%s\n' "$out" | sed -n '1p')" "[ssh login]" "ssh login is first"
  assert_eq "$(printf '%s\n' "$out" | sed -n '2p')" "main" "sessions follow login"
  assert_eq "$(printf '%s\n' "$out" | sed -n '3p')" "work" "second session in middle"
  assert_eq "$(printf '%s\n' "$out" | sed -n '4p')" "[new session]" "new session is last"
  pass "fssh session menu order with sessions ($DEVTOOLS_TEST_PROFILE)"
}

test_session_menu_order_without_sessions() {
  local out
  out="$(run_fssh_fn session_menu_entries '')"
  assert_eq "$(printf '%s\n' "$out")" $'[ssh login]\n[new session]' "login then new when empty"
  pass "fssh session menu order without sessions ($DEVTOOLS_TEST_PROFILE)"
}

# bash -lc may print nvm/npmrc warnings on stderr; they must not become fzf rows.
test_list_remote_sessions_ignores_stderr_noise() {
  local out
  out="$(
    FSSH_NO_MAIN=1 /bin/bash -c '
      set -euo pipefail
      # shellcheck disable=SC1090
      source "$1"
      remote_tmux() {
        printf "%s\n" "nvm is not compatible with the npm config \"prefix\" option: currently set to \"/home/x/.npm-global\"" >&2
        printf "%s\n" "Run '\''nvm use --delete-prefix'\'' to unset it." >&2
        printf "%s\n" "main"
        printf "%s\n" "work"
        return 0
      }
      list_remote_sessions some-host
    ' _ "$FSSH_SH"
  )"
  assert_eq "$out" $'main\nwork' "session list uses tmux stdout only"
  assert_not_contains "$out" "nvm" "nvm stderr is not treated as a session"
  pass "fssh list_remote_sessions ignores stderr noise ($DEVTOOLS_TEST_PROFILE)"
}

# bash -lc misses ~/.zprofile, so Apple Silicon Homebrew tmux is invisible
# unless common prefixes are added on the remote before invoking tmux.
test_remote_tmux_prepends_common_bin_paths() {
  local out
  out="$(
    FSSH_NO_MAIN=1 /bin/bash -c '
      set -euo pipefail
      # shellcheck disable=SC1090
      source "$1"
      mssh() {
        local a
        for a in "$@"; do
          printf "[%s]\n" "$a"
        done
      }
      remote_tmux -t mac-host new-session -As main
    ' _ "$FSSH_SH"
  )"
  assert_contains "$out" $'[-t]\n[mac-host]' "forwards -t then host"
  assert_contains "$out" "/opt/homebrew/bin" "includes Apple Silicon Homebrew bin"
  assert_contains "$out" "/usr/local/bin" "includes Intel Homebrew / usr local bin"
  assert_contains "$out" ".local/bin" "includes ~/.local/bin"
  assert_contains "$out" "bash -lc" "still uses a login bash"
  assert_contains "$out" "new-session" "forwards tmux subcommand"
  assert_contains "$out" "main" "forwards session name"
  assert_not_contains "$out" "${HOME}/.local/bin" "does not bake local HOME into remote PATH"
  pass "fssh remote_tmux prepends common bin paths ($DEVTOOLS_TEST_PROFILE)"
}

test_list_remote_sessions_failure_warns_from_stderr() {
  local out err
  err="$(mktemp "${TMPDIR:-/tmp}/fssh-sess-err.XXXXXX")"
  out="$(
    FSSH_NO_MAIN=1 /bin/bash -c '
      set -euo pipefail
      # shellcheck disable=SC1090
      source "$1"
      remote_tmux() {
        printf "%s\n" "tmux: command not found" >&2
        return 1
      }
      list_remote_sessions some-host
    ' _ "$FSSH_SH" 2>"$err"
  )" || true
  assert_eq "$out" "" "failed list yields no session stdout"
  assert_contains "$(cat "$err")" "tmux: command not found" "warn includes remote stderr"
  assert_not_contains "$out" "tmux: command not found" "stderr is not session stdout"
  rm -f "$err"
  pass "fssh list_remote_sessions failure uses stderr ($DEVTOOLS_TEST_PROFILE)"
}

# Interactive fssh calls list_hosts before fzf; keep that path snappy.
# Hermetic PATH links a real tr; temporarily wrap it with latency so per-line
# `tr` usage (the previous Include-parser regression) exceeds the budget even
# on fast CI hosts, while a fork-free parser stays well under 1.5s.
test_list_hosts_perf_budget_50_hosts() {
  write_hosts_config_perf50
  local out out_file count elapsed_s elapsed_ms real_tr
  local budget_ms=1500
  out_file="$(mktemp "${TMPDIR:-/tmp}/fssh-perf.XXXXXX")"
  real_tr="$(readlink "$FAKE_BIN/tr" 2>/dev/null || true)"
  [[ -n "$real_tr" && -x "$real_tr" ]] || {
    echo "FAIL: expected FAKE_BIN/tr symlink to a real tr" >&2
    return 1
  }

  # Replace the symlink (do not write through it — that would target the real binary).
  rm -f "$FAKE_BIN/tr"
  cat >"$FAKE_BIN/tr" <<EOF
#!/usr/bin/env bash
# 10ms penalty per invocation — ~200 config lines ⇒ ~2s if called per line.
sleep 0.01
exec '$real_tr' "\$@"
EOF
  chmod +x "$FAKE_BIN/tr"

  # Bash TIMEFORMAT reports fractional seconds portably (incl. Bash 3.2).
  local list_rc=0
  elapsed_s="$(
    TIMEFORMAT='%R'
    { time run_fssh_fn list_hosts >"$out_file"; } 2>&1
  )" || list_rc=$?
  out="$(cat "$out_file" 2>/dev/null || true)"
  rm -f "$out_file"
  ln -sf "$real_tr" "$FAKE_BIN/tr"
  [[ "$list_rc" -eq 0 ]] || return "$list_rc"
  elapsed_ms="$(awk -v e="$elapsed_s" 'BEGIN { printf "%d", (e * 1000) + 0.5 }')"

  count="$(printf '%s\n' "$out" | grep -c . || true)"
  assert_eq "$count" "50" "perf fixture yields 50 concrete hosts"
  assert_contains "$out" "host-01" "perf fixture includes first host"
  assert_contains "$out" "host-50" "perf fixture includes included host"
  assert_not_contains "$out" "jump-*" "perf fixture still excludes wildcards"

  if [[ "$elapsed_ms" -gt "$budget_ms" ]]; then
    echo "FAIL: list_hosts took ${elapsed_ms}ms (budget ${budget_ms}ms) for ~50 hosts" >&2
    return 1
  fi
  pass "fssh list_hosts perf <=${budget_ms}ms for ~50 hosts (${elapsed_ms}ms, $DEVTOOLS_TEST_PROFILE)"
}

test_add_host() {
  local out rc target before backup
  rm -rf "$HOME/.ssh"
  export FSSH_TEST_LOG="$HOME/add.log"
  : >"$FSSH_TEST_LOG"
  cat >"$FAKE_BIN/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'keygen %s\n' "$*" >>"$FSSH_TEST_LOG"
while [[ "$1" != "-f" ]]; do shift; done
printf 'private\n' >"$2"
printf 'public\n' >"$2.pub"
EOF
  cat >"$FAKE_BIN/ssh-copy-id" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'copy %s\n' "$*" >>"$FSSH_TEST_LOG"
exit "${FSSH_COPY_RC:-0}"
EOF
  cat >"$FAKE_BIN/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ssh %s\n' "$*" >>"$FSSH_TEST_LOG"
exit "${FSSH_SSH_RC:-0}"
EOF
  chmod +x "$FAKE_BIN/ssh-keygen" "$FAKE_BIN/ssh-copy-id" "$FAKE_BIN/ssh"

  out="$(bash "$FSSH_SH" -a deploy@10.1.2.3:2222 --dry-run 2>&1)"
  assert_contains "$out" "deploy-10.1.2.3-2222" "dry-run shows alias"
  [[ ! -e "$HOME/.ssh" && ! -s "$FSSH_TEST_LOG" ]] || return 1

  for target in 'missing-user' 'u@host:0' 'u@host:65536' 'u@host:abc' 'u@host:22:23' $'u@host\nHost evil' '-oops'; do
    rc=0
    bash "$FSSH_SH" -a "$target" --dry-run >/dev/null 2>&1 || rc=$?
    [[ "$rc" -ne 0 ]] || { echo "FAIL: accepted invalid target $target" >&2; return 1; }
  done
  rc=0
  bash "$FSSH_SH" -a u@host -n >/dev/null 2>&1 || rc=$?
  [[ "$rc" -ne 0 ]] || return 1
  [[ ! -e "$HOME/.ssh" && ! -s "$FSSH_TEST_LOG" ]] || return 1

  mkdir -p "$HOME/.ssh/config.d"
  printf 'Include config.d/work\nHost *\n    User fallback\n    Port 99\n' >"$HOME/.ssh/config"
  printf 'Host included-host\n    HostName example.org\n' >"$HOME/.ssh/config.d/work"
  before="$(cat "$HOME/.ssh/config")"
  out="$(bash "$FSSH_SH" --add deploy@example.com:2222 2>&1)"
  assert_contains "$out" "deploy-example.com-2222" "success reports alias"
  assert_contains "$(cat "$FSSH_TEST_LOG")" "copy -F /dev/null" "copies key without user config"
  assert_contains "$(cat "$FSSH_TEST_LOG")" "-p 2222" "uses requested port"
  assert_contains "$(cat "$FSSH_TEST_LOG")" "BatchMode=yes" "verifies passwordless login"
  assert_contains "$(cat "$HOME/.ssh/config")" "Host deploy-example.com-2222" "writes host"
  assert_contains "$(cat "$HOME/.ssh/config")" "Include config.d/work" "preserves existing config"
  assert_contains "$(run_fssh_fn list_hosts)" "included-host" "preserves Include discovery"
  backup="$(cat "$HOME"/.ssh/config.bak.*)"
  assert_eq "$backup" "$before" "backup preserves original"
  [[ ! -r "$HOME/.ssh/config" || ! -x "$HOME/.ssh/config" ]] || return 1

  : >"$FSSH_TEST_LOG"
  rc=0
  bash "$FSSH_SH" -a deploy@example.com:2222 >/dev/null 2>&1 || rc=$?
  [[ "$rc" -ne 0 && ! -s "$FSSH_TEST_LOG" ]] || return 1
  printf 'Host admin-example.net\n' >>"$HOME/.ssh/config.d/work"
  rc=0
  bash "$FSSH_SH" -a admin@example.net >/dev/null 2>&1 || rc=$?
  [[ "$rc" -ne 0 && ! -s "$FSSH_TEST_LOG" ]] || return 1

  before="$(cat "$HOME/.ssh/config")"
  rc=0
  FSSH_COPY_RC=1 bash "$FSSH_SH" -a other@example.net >/dev/null 2>&1 || rc=$?
  [[ "$rc" -ne 0 ]] || return 1
  assert_eq "$(cat "$HOME/.ssh/config")" "$before" "copy failure leaves config unchanged"
  rc=0
  FSSH_SSH_RC=1 bash "$FSSH_SH" -a other@example.net >/dev/null 2>&1 || rc=$?
  [[ "$rc" -ne 0 ]] || return 1
  assert_eq "$(cat "$HOME/.ssh/config")" "$before" "verification failure leaves config unchanged"
  : >"$FSSH_TEST_LOG"
  bash "$FSSH_SH" -a other@example.net >/dev/null 2>&1
  assert_not_contains "$(cat "$FSSH_TEST_LOG")" "keygen" "reuses existing key"
  assert_contains "$(cat "$HOME/.ssh/config")" "Host other-example.net" "adds hostname at default port"
  pass "fssh add host scenarios ($DEVTOOLS_TEST_PROFILE)"
}

test_setup_help
test_fssh_help_mentions_query
test_list_hosts_follows_include
test_list_hosts_follows_tilde_include
test_match_hosts_from_include
test_match_hosts_exact
test_match_hosts_exact_beats_substring
test_match_hosts_substring_unique
test_match_hosts_substring_multiple
test_match_hosts_ignores_wildcards
test_resolve_host_unique
test_resolve_host_none
test_resolve_host_multiple_uses_fzf
test_match_sessions_exact
test_match_sessions_exact_beats_substring
test_match_sessions_substring_unique
test_match_sessions_substring_multiple
test_resolve_session_unique
test_resolve_session_none
test_resolve_session_multiple_uses_fzf
test_fssh_tmux_requires_host
test_fssh_tmux_conflicts_with_no_tmux
test_session_menu_order_with_sessions
test_session_menu_order_without_sessions
test_list_remote_sessions_ignores_stderr_noise
test_remote_tmux_prepends_common_bin_paths
test_list_remote_sessions_failure_warns_from_stderr
test_list_hosts_perf_budget_50_hosts
test_add_host

echo "PASS: ssh suite complete ($DEVTOOLS_TEST_PROFILE)"
