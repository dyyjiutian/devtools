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
test_session_menu_order_with_sessions
test_session_menu_order_without_sessions

echo "PASS: ssh suite complete ($DEVTOOLS_TEST_PROFILE)"
