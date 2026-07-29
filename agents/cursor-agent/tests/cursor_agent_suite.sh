#!/usr/bin/env bash
# Cursor Agent module suite — fake agent/git + isolated HOME
set -euo pipefail

SETUP_SH="$MODULE_ROOT/setup.sh"
MP_LOG="$HOME/.fake-agent-marketplace.log"
GIT_LOG="$HOME/.fake-git.log"

install_fakes() {
  mkdir -p "$FAKE_BIN" "$HOME"
  : >"$MP_LOG"
  : >"$GIT_LOG"

  cat >"$FAKE_BIN/agent" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG="${HOME}/.fake-agent-marketplace.log"
cmd="${1:-}"
case "$cmd" in
  --version) echo "agent-fake 0.0.0"; exit 0 ;;
  plugin)
    if [[ "${2:-}" == "marketplace" ]]; then
      action="${3:-}"
      case "$action" in
        list)
          if [[ -f "$LOG" ]]; then
            while IFS= read -r line || [[ -n "$line" ]]; do
              [[ -z "$line" ]] && continue
              name="$(basename "${line%/}")"
              name="${name%.git}"
              echo "$name  user  $line"
            done <"$LOG"
          fi
          exit 0
          ;;
        add)
          url="${4:-}"
          echo "$url" >>"$LOG"
          exit 0
          ;;
      esac
    fi
    ;;
  status|whoami) echo "logged-in-fake"; exit 0 ;;
esac
echo "fake agent: unhandled: $*" >&2
exit 1
EOF
  chmod +x "$FAKE_BIN/agent"

  # Fake git: clone creates a mini skill tree; pull is no-op
  # Remove host-linked git first so we do not follow the symlink.
  rm -f "$FAKE_BIN/git"
  cat >"$FAKE_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG="${HOME}/.fake-git.log"
echo "$*" >>"$LOG"
cmd="${1:-}"
if [[ "$cmd" == "clone" ]]; then
  # git clone --depth 1 URL DEST
  dest=""
  url=""
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --depth) shift 2 ;;
      -*) shift ;;
      *)
        if [[ -z "$url" ]]; then url="$1"; else dest="$1"; fi
        shift
        ;;
    esac
  done
  mkdir -p "$dest/.git"
  for skill in brainstorming systematic-debugging test-driven-development \
      verification-before-completion writing-plans; do
    mkdir -p "$dest/skills/$skill"
    printf '%s\n' "---" "name: ${skill}" "description: fake" "---" "" "# ${skill}" \
      >"$dest/skills/$skill/SKILL.md"
  done
  exit 0
fi
if [[ "$cmd" == "-C" ]]; then
  # git -C cache pull --ff-only
  exit 0
fi
# Allow other git invocations used by cookbook/status to no-op succeed
exit 0
EOF
  chmod +x "$FAKE_BIN/git"
}

test_help() {
  local out
  out="$(bash "$SETUP_SH" --help 2>&1)"
  assert_contains "$out" "install-plugins" "help mentions install-plugins"
  assert_contains "$out" "Shell(*)" "help mentions Shell(*)"
  assert_contains "$out" "deny" "help mentions deny"
  pass "cursor-agent setup --help ($DEVTOOLS_TEST_PROFILE)"
}

test_install_plugins_list() {
  local out
  out="$(bash "$SETUP_SH" install-plugins --list 2>&1)"
  assert_contains "$out" "superpowers" "list includes marketplace superpowers"
  assert_contains "$out" "git-submit" "list includes git-submit"
  assert_contains "$out" "brainstorming" "list includes brainstorming skill"
  pass "cursor-agent install-plugins --list ($DEVTOOLS_TEST_PROFILE)"
}

test_sync_wide_allow_and_deny() {
  install_fakes
  # Pre-existing config with sensitive allow entry
  mkdir -p "$HOME/.cursor"
  cat >"$HOME/.cursor/cli-config.json" <<'EOF'
{
  "version": 1,
  "approvalMode": "allowlist",
  "permissions": {
    "allow": ["Shell(rm)", "Shell(ls)"],
    "deny": []
  }
}
EOF
  bash "$SETUP_SH" sync >/dev/null 2>&1
  local cfg
  cfg="$(cat "$HOME/.cursor/cli-config.json")"
  assert_contains "$cfg" '"Shell(*)"' "sync writes Shell(*)"
  assert_contains "$cfg" '"Read(**)"' "sync writes Read(**)"
  assert_contains "$cfg" '"Write(**)"' "sync writes Write(**)"
  assert_contains "$cfg" '"WebFetch(*)"' "sync writes WebFetch(*)"
  assert_contains "$cfg" '"Mcp(*)"' "sync writes Mcp(*)"
  assert_contains "$cfg" '"Shell(rm)"' "sync keeps Shell(rm) somewhere"
  # Shell(rm) must be in deny, not allow — check via node
  CURSOR_AGENT_CONFIG="$HOME/.cursor/cli-config.json" node <<'EOF'
const fs = require('fs');
const s = JSON.parse(fs.readFileSync(process.env.CURSOR_AGENT_CONFIG, 'utf8'));
const allow = s.permissions.allow || [];
const deny = s.permissions.deny || [];
if (allow.includes('Shell(rm)')) { console.error('Shell(rm) still in allow'); process.exit(1); }
if (!deny.includes('Shell(rm)')) { console.error('Shell(rm) missing from deny'); process.exit(1); }
if (!allow.includes('Shell(ls)')) { console.error('user allow Shell(ls) not preserved'); process.exit(1); }
EOF
  # idempotent
  bash "$SETUP_SH" sync >/dev/null 2>&1
  local count
  count="$(grep -c '"Shell(\*)"' "$HOME/.cursor/cli-config.json" || true)"
  assert_eq "$count" "1" "Shell(*) appears once after repeated sync"
  pass "cursor-agent sync wide allow + deny ($DEVTOOLS_TEST_PROFILE)"
}

test_install_plugins_single_skill() {
  install_fakes
  bash "$SETUP_SH" install-plugins brainstorming >/dev/null 2>&1
  assert_symlink "$HOME/.cursor/skills/brainstorming" "brainstorming skill linked"
  assert_file_exists "$HOME/.cursor/skills/brainstorming/SKILL.md"
  [[ ! -e "$HOME/.cursor/skills/writing-plans" ]] || {
    echo "FAIL: single skill install should not link writing-plans" >&2
    return 1
  }
  pass "cursor-agent install-plugins single skill ($DEVTOOLS_TEST_PROFILE)"
}

test_install_plugins_marketplace_and_cookbook() {
  install_fakes
  bash "$SETUP_SH" install-plugins superpowers cookbook >/dev/null 2>&1
  assert_contains "$(cat "$MP_LOG")" "obra/superpowers" "marketplace added"
  # cookbook git-submit skill name from frontmatter
  assert_symlink "$HOME/.cursor/skills/git-submit" "cookbook git-submit linked" || \
    assert_file_exists "$HOME/.cursor/skills/git-submit/SKILL.md"
  pass "cursor-agent install-plugins marketplace+cookbook ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_install_plugins_list
test_sync_wide_allow_and_deny
test_install_plugins_single_skill
test_install_plugins_marketplace_and_cookbook

echo "PASS: cursor-agent suite complete ($DEVTOOLS_TEST_PROFILE)"
