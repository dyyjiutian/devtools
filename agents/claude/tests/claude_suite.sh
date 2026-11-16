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

install_fake_npm() {
  cat >"$FAKE_BIN/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
PREFIX="${FAKE_NPM_PREFIX:?FAKE_NPM_PREFIX not set}"
SCOPE="${FAKE_NPM_SCOPE:?FAKE_NPM_SCOPE not set}"
PKG="${FAKE_NPM_PKG:?FAKE_NPM_PKG not set}"
LOG="$HOME/.fake-npm.log"
cmd="${1:-}"
case "$cmd" in
  root)   echo "$PREFIX/lib/node_modules"; exit 0 ;;
  prefix) echo "$PREFIX"; exit 0 ;;
  install)
    shift
    echo "install $*" >>"$LOG"
    # Record retired leftovers still present at install time (ordering check)
    for d in "$PREFIX/lib/node_modules/$SCOPE/.$PKG-"* "$PREFIX/bin/.$PKG-"*; do
      if [[ -e "$d" || -L "$d" ]]; then
        echo "leftover-at-install $d" >>"$LOG"
      fi
    done
    exit 0
    ;;
esac
echo "fake npm: unhandled: $*" >&2
exit 1
EOF
  chmod +x "$FAKE_BIN/npm"
}

test_help() {
  local out
  out="$(bash "$SETUP_SH" --help 2>&1)"
  assert_contains "$out" "install-plugins" "help mentions install-plugins"
  assert_contains "$out" "--list" "help mentions --list"
  pass "claude setup --help ($DEVTOOLS_TEST_PROFILE)"
}

test_install_cleans_npm_retired_leftovers() {
  install_fake_claude
  install_fake_npm
  local prefix="$HOME/.npm-global"
  export FAKE_NPM_PREFIX="$prefix" FAKE_NPM_SCOPE="@anthropic-ai" FAKE_NPM_PKG="claude-code"
  local scope_dir="$prefix/lib/node_modules/@anthropic-ai"
  mkdir -p "$scope_dir/.claude-code-RET123" "$scope_dir/claude-code" "$prefix/bin"
  echo stale >"$scope_dir/.claude-code-RET123/package.json"
  echo '{"name":"@anthropic-ai/claude-code"}' >"$scope_dir/claude-code/package.json"
  ln -s ../lib/node_modules/@anthropic-ai/claude-code/cli.js "$prefix/bin/.claude-code-BIN123"
  printf 'y\n' | bash "$SETUP_SH" install >/dev/null 2>&1
  assert_contains "$(cat "$HOME/.fake-npm.log")" "install -g @anthropic-ai/claude-code" "npm install -g invoked"
  assert_not_contains "$(cat "$HOME/.fake-npm.log")" "leftover-at-install" \
    "retired leftovers cleaned before npm install"
  if [[ -e "$scope_dir/.claude-code-RET123" || -L "$prefix/bin/.claude-code-BIN123" ]]; then
    echo "FAIL: retired leftovers still present after install" >&2
    return 1
  fi
  assert_file_exists "$scope_dir/claude-code/package.json"
  # Rerun without leftovers must stay clean (idempotent)
  printf 'y\n' | bash "$SETUP_SH" install >/dev/null 2>&1
  assert_eq "$(grep -c '^install ' "$HOME/.fake-npm.log")" "2" "second install still runs npm"
  pass "claude install cleans npm retired leftovers ($DEVTOOLS_TEST_PROFILE)"
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

test_template_deny_excludes_root_glob() {
  local settings="$MODULE_ROOT/config/settings.json"
  assert_file_exists "$settings"
  # Broad /* deny matches /tmp/... and permanently blocks cleanup after ask.
  assert_not_contains "$(cat "$settings")" '"Bash(rm -rf /*)"' \
    "template must not deny Bash(rm -rf /*)"
  assert_not_contains "$(cat "$settings")" '"Bash(rm -fr /*)"' \
    "template must not deny Bash(rm -fr /*)"
  assert_contains "$(cat "$settings")" '"Bash(rm -rf /)"' \
    "template still denies exact rm -rf /"
  assert_contains "$(cat "$settings")" '"Bash(rm -rf *)"' \
    "template still asks for general rm -rf"
  pass "claude template deny excludes root glob ($DEVTOOLS_TEST_PROFILE)"
}

test_sync_strips_obsolete_root_glob_deny() {
  mkdir -p "$HOME/.claude"
  cat >"$HOME/.claude/settings.json" <<'EOF'
{
  "permissions": {
    "defaultMode": "default",
    "allow": ["Bash"],
    "ask": ["Bash(rm -rf *)"],
    "deny": [
      "Bash(rm -rf /*)",
      "Bash(rm -fr /*)",
      "Bash(/bin/rm -rf /*)",
      "Bash(sudo rm -rf /*)",
      "Bash(rm -rf /)"
    ]
  },
  "customKeep": true
}
EOF
  bash "$SETUP_SH" sync >/dev/null 2>&1
  local cfg="$HOME/.claude/settings.json"
  assert_file_exists "$cfg"
  assert_not_contains "$(cat "$cfg")" '"Bash(rm -rf /*)"' \
    "sync strips obsolete Bash(rm -rf /*)"
  assert_not_contains "$(cat "$cfg")" '"Bash(rm -fr /*)"' \
    "sync strips obsolete Bash(rm -fr /*)"
  assert_not_contains "$(cat "$cfg")" '"Bash(/bin/rm -rf /*)"' \
    "sync strips obsolete /bin/rm -rf /*"
  assert_not_contains "$(cat "$cfg")" '"Bash(sudo rm -rf /*)"' \
    "sync strips obsolete sudo rm -rf /*"
  assert_contains "$(cat "$cfg")" '"Bash(rm -rf /)"' \
    "sync keeps exact root deny"
  assert_contains "$(cat "$cfg")" '"customKeep": true' \
    "sync preserves unrelated user fields"
  assert_contains "$(cat "$cfg")" '"defaultMode": "bypassPermissions"' \
    "sync initializes the managed permission mode from the template"
  pass "claude sync strips obsolete root-glob deny ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_install_cleans_npm_retired_leftovers
test_install_plugins_list
test_install_plugins_single
test_install_plugins_all_idempotent
test_template_deny_excludes_root_glob
test_sync_strips_obsolete_root_glob_deny

echo "PASS: claude suite complete ($DEVTOOLS_TEST_PROFILE)"
