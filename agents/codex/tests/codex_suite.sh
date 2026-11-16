#!/usr/bin/env bash
# Codex module suite — fake `codex` + isolated HOME
set -euo pipefail

SETUP_SH="$MODULE_ROOT/setup.sh"
INSTALL_LOG="$HOME/.fake-codex-install.log"
INSTALLED_FILE="$HOME/.fake-codex-installed"
FEATURES_LOG="$HOME/.fake-codex-features.log"

install_fake_codex() {
  mkdir -p "$FAKE_BIN" "$HOME/.codex"
  : >"$INSTALL_LOG"
  : >"$INSTALLED_FILE"
  : >"$FEATURES_LOG"
  cat >"$FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG="${HOME}/.fake-codex-install.log"
INST="${HOME}/.fake-codex-installed"
FLOG="${HOME}/.fake-codex-features.log"
cmd="${1:-}"
sub="${2:-}"
case "$cmd" in
  --version) echo "codex-fake 0.0.0"; exit 0 ;;
  features)
    case "$sub" in
      disable)
        echo "disable ${3:-}" >>"$FLOG"
        # Also write config like the real CLI would
        mkdir -p "${HOME}/.codex"
        conf="${HOME}/.codex/config.toml"
        if [[ -f "$conf" ]] && grep -q '^\[features\]' "$conf"; then
          awk '
            BEGIN { in_f=0; done=0 }
            /^\[features\]/ { in_f=1; print; next }
            /^\[/ { if (in_f && !done) { print "apps = false"; done=1 } in_f=0; print; next }
            in_f && /^apps[[:space:]]*=/ { if (!done) { print "apps = false"; done=1 } next }
            { print }
            END { if (in_f && !done) print "apps = false" }
          ' "$conf" >"${conf}.tmp" && mv "${conf}.tmp" "$conf"
        else
          printf '\n[features]\napps = false\n' >>"$conf"
        fi
        exit 0
        ;;
      list) echo "apps stable true"; exit 0 ;;
    esac
    ;;
  plugin)
    case "$sub" in
      list)
        if [[ "${3:-}" == "--json" ]]; then
          node -e '
            const fs = require("fs");
            const inst = fs.existsSync(process.env.HOME + "/.fake-codex-installed")
              ? fs.readFileSync(process.env.HOME + "/.fake-codex-installed", "utf8").trim().split(/\n/).filter(Boolean)
              : [];
            const installed = inst.map((id) => {
              const [name, marketplaceName] = id.split("@");
              return { pluginId: id, name, marketplaceName, installed: true, enabled: true };
            });
            process.stdout.write(JSON.stringify({ installed, available: [] }));
          '
          exit 0
        fi
        while IFS= read -r line || [[ -n "$line" ]]; do
          [[ -z "$line" ]] && continue
          printf '%-40s installed\n' "$line"
        done <"$INST"
        exit 0
        ;;
      add)
        plugin="${3:-}"
        echo "add $plugin" >>"$LOG"
        echo "$plugin" >>"$INST"
        exit 0
        ;;
    esac
    ;;
esac
echo "fake codex: unhandled: $*" >&2
exit 1
EOF
  chmod +x "$FAKE_BIN/codex"
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
  assert_contains "$out" "superpowers" "help mentions superpowers"
  pass "codex setup --help ($DEVTOOLS_TEST_PROFILE)"
}

test_install_cleans_npm_retired_leftovers() {
  install_fake_codex
  install_fake_npm
  local prefix="$HOME/.npm-global"
  export FAKE_NPM_PREFIX="$prefix" FAKE_NPM_SCOPE="@openai" FAKE_NPM_PKG="codex"
  local scope_dir="$prefix/lib/node_modules/@openai"
  mkdir -p "$scope_dir/.codex-RET123" "$scope_dir/codex" "$prefix/bin"
  echo stale >"$scope_dir/.codex-RET123/package.json"
  echo '{"name":"@openai/codex"}' >"$scope_dir/codex/package.json"
  ln -s ../lib/node_modules/@openai/codex/bin/codex.js "$prefix/bin/.codex-BIN123"
  printf 'y\n' | bash "$SETUP_SH" install >/dev/null 2>&1
  assert_contains "$(cat "$HOME/.fake-npm.log")" "install -g @openai/codex" "npm install -g invoked"
  assert_not_contains "$(cat "$HOME/.fake-npm.log")" "leftover-at-install" \
    "retired leftovers cleaned before npm install"
  if [[ -e "$scope_dir/.codex-RET123" || -L "$prefix/bin/.codex-BIN123" ]]; then
    echo "FAIL: retired leftovers still present after install" >&2
    return 1
  fi
  assert_file_exists "$scope_dir/codex/package.json"
  # Rerun without leftovers must stay clean (idempotent)
  printf 'y\n' | bash "$SETUP_SH" install >/dev/null 2>&1
  assert_eq "$(grep -c '^install ' "$HOME/.fake-npm.log")" "2" "second install still runs npm"
  pass "codex install cleans npm retired leftovers ($DEVTOOLS_TEST_PROFILE)"
}

test_install_plugins_list() {
  local out
  out="$(bash "$SETUP_SH" install-plugins --list 2>&1)"
  assert_contains "$out" "superpowers" "list includes superpowers"
  assert_contains "$out" "coderabbit" "list includes coderabbit"
  assert_contains "$out" "openai-curated" "list shows marketplace"
  pass "codex install-plugins --list ($DEVTOOLS_TEST_PROFILE)"
}

test_install_plugins_single() {
  install_fake_codex
  bash "$SETUP_SH" install-plugins github >/dev/null 2>&1
  assert_contains "$(cat "$INSTALL_LOG")" "add github@openai-curated" "single install github"
  assert_not_contains "$(cat "$INSTALL_LOG")" "add superpowers@" "should not install superpowers"
  pass "codex install-plugins single ($DEVTOOLS_TEST_PROFILE)"
}

test_sync_disables_apps() {
  install_fake_codex
  mkdir -p "$HOME/.codex"
  printf 'model = "gpt-test"\n' >"$HOME/.codex/config.toml"
  bash "$SETUP_SH" sync >/dev/null 2>&1
  assert_contains "$(cat "$FEATURES_LOG")" "disable apps" "sync calls features disable apps"
  assert_contains "$(cat "$HOME/.codex/config.toml")" "apps = false" "config has apps = false"
  # idempotent
  bash "$SETUP_SH" sync >/dev/null 2>&1
  local count
  count="$(grep -c 'apps = false' "$HOME/.codex/config.toml" || true)"
  [[ "$count" -ge 1 ]] || {
    echo "FAIL: expected apps = false in config" >&2
    return 1
  }
  pass "codex sync disables features.apps ($DEVTOOLS_TEST_PROFILE)"
}

test_install_plugins_idempotent() {
  install_fake_codex
  bash "$SETUP_SH" install-plugins >/dev/null 2>&1
  local first
  first="$(wc -l <"$INSTALL_LOG" | tr -d ' ')"
  bash "$SETUP_SH" install-plugins >/dev/null 2>&1
  local second
  second="$(wc -l <"$INSTALL_LOG" | tr -d ' ')"
  assert_eq "$second" "$first" "second install-plugins skips installed"
  pass "codex install-plugins idempotent ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_install_cleans_npm_retired_leftovers
test_install_plugins_list
test_install_plugins_single
test_sync_disables_apps
test_install_plugins_idempotent

echo "PASS: codex suite complete ($DEVTOOLS_TEST_PROFILE)"
