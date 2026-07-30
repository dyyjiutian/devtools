#!/usr/bin/env bash
# Claude module suite — fake `claude` + isolated HOME
set -euo pipefail

SETUP_SH="$MODULE_ROOT/setup.sh"
INSTALL_LOG="$HOME/.fake-claude-install.log"
INSTALLED_FILE="$HOME/.fake-claude-installed"

install_fake_claude() {
  mkdir -p "$FAKE_BIN" "$HOME"
  : >"$INSTALL_LOG"
  : >"$INSTALLED_FILE"
  cat >"$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG="${HOME}/.fake-claude-install.log"
INST="${HOME}/.fake-claude-installed"
cmd="${1:-}"
sub="${2:-}"
case "$cmd" in
  --version) echo "claude-fake 0.0.0"; exit 0 ;;
  plugins)
    case "$sub" in
      list)
        while IFS= read -r line || [[ -n "$line" ]]; do
          [[ -z "$line" ]] && continue
          echo "  ❯ ${line}"
          echo "    Version: 0.0.0"
          echo "    Status: enabled"
        done <"$INST"
        if [[ "${CLAUDE_FAKE_LARGE_LIST:-0}" == "1" ]]; then
          for _ in {1..4096}; do
            echo "    Metadata: filler to exercise long plugin-list output"
          done
        fi
        exit 0
        ;;
      install)
        plugin="${3:-}"
        echo "install $plugin" >>"$LOG"
        echo "$plugin" >>"$INST"
        exit 0
        ;;
      marketplace)
        action="${3:-}"
        echo "marketplace $action ${4:-} ${5:-}" >>"$LOG"
        exit 0
        ;;
    esac
    ;;
esac
echo "fake claude: unhandled: $*" >&2
exit 1
EOF
  chmod +x "$FAKE_BIN/claude"
}

test_help() {
  local out
  out="$(bash "$SETUP_SH" --help 2>&1)"
  assert_contains "$out" "install-plugins" "help mentions install-plugins"
  assert_contains "$out" "--list" "help mentions --list"
  pass "claude setup --help ($DEVTOOLS_TEST_PROFILE)"
}

test_install_plugins_list() {
  local out
  out="$(bash "$SETUP_SH" install-plugins --list 2>&1)"
  assert_contains "$out" "superpowers" "list includes superpowers"
  assert_contains "$out" "context7" "list includes context7"
  assert_contains "$out" "claude-hud" "list includes claude-hud"
  assert_contains "$out" "github" "list includes github"
  pass "claude install-plugins --list ($DEVTOOLS_TEST_PROFILE)"
}

test_install_plugins_single() {
  install_fake_claude
  bash "$SETUP_SH" install-plugins superpowers >/dev/null 2>&1
  assert_file_exists "$INSTALL_LOG"
  assert_contains "$(cat "$INSTALL_LOG")" "install superpowers@claude-plugins-official" \
    "single install uses full plugin id"
  assert_not_contains "$(cat "$INSTALL_LOG")" "install context7@" \
    "single install should not install context7"
  pass "claude install-plugins single ($DEVTOOLS_TEST_PROFILE)"
}

test_install_plugins_all_idempotent() {
  install_fake_claude
  bash "$SETUP_SH" install-plugins >/dev/null 2>&1
  local first second
  first="$(grep -c '^install ' "$INSTALL_LOG" || true)"
  CLAUDE_FAKE_LARGE_LIST=1 bash "$SETUP_SH" install-plugins >/dev/null 2>&1
  second="$(grep -c '^install ' "$INSTALL_LOG" || true)"
  assert_eq "$second" "$first" "second install-plugins should skip already installed"
  [[ "$first" -ge 3 ]] || {
    echo "FAIL: expected at least core plugins installed, got $first install lines" >&2
    return 1
  }
  pass "claude install-plugins idempotent ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_install_plugins_list
test_install_plugins_single
test_install_plugins_all_idempotent

echo "PASS: claude suite complete ($DEVTOOLS_TEST_PROFILE)"
