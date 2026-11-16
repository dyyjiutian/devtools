#!/usr/bin/env bash
# Bash module integration tests split from the former repository-wide suite.
set -euo pipefail

SETUP_SH="$MODULE_ROOT/setup.sh"
TMP_DIR="$HOME/bash-integration"
mkdir -p "$TMP_DIR"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_contains() {
  local file="$1" expected="$2"
  grep -Fq -- "$expected" "$file" || fail "expected '$expected' in $file"
}

assert_not_contains() {
  local file="$1" unexpected="$2"
  ! grep -Fq -- "$unexpected" "$file" || fail "did not expect '$unexpected' in $file"
}

if [[ "$DEVTOOLS_TEST_PROFILE" != "macos" ]]; then
# Starship cache must be used before the online installer.
mkdir -p "$TMP_DIR/cache/binaries" "$TMP_DIR/home/.local/share/blesh" "$TMP_DIR/bin"
touch "$TMP_DIR/home/.local/share/blesh/ble.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP_DIR/bin/git"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP_DIR/bin/zoxide"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP_DIR/bin/fzf"
cat > "$TMP_DIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
touch "$CURL_FAILURE_MARKER"
exit 97
EOF
chmod +x "$TMP_DIR/bin/git" "$TMP_DIR/bin/zoxide" "$TMP_DIR/bin/fzf" "$TMP_DIR/bin/curl"

mkdir -p "$TMP_DIR/starship-payload"
printf '#!/usr/bin/env bash\necho cached-starship\n' > "$TMP_DIR/starship-payload/starship"
chmod +x "$TMP_DIR/starship-payload/starship"
tar -czf "$TMP_DIR/cache/binaries/starship-x86_64-unknown-linux-musl.tar.gz"   -C "$TMP_DIR/starship-payload" starship

CURL_FAILURE_MARKER="$TMP_DIR/curl-called" PATH="$TMP_DIR/bin:$FAKE_BIN" HOME="$TMP_DIR/home" DEVTOOLS_CACHE_DIR="$TMP_DIR/cache" bash "$SETUP_SH" > "$TMP_DIR/starship.log" 2>&1 ||
  fail "Starship cache install failed; output: $(cat "$TMP_DIR/starship.log")"
assert_file "$TMP_DIR/home/.local/bin/starship"
[[ ! -e "$TMP_DIR/curl-called" ]] || fail "online installer was called despite a valid cache"

# A previous interrupted fzf install may leave ~/.fzf behind even though fzf
# is not yet on PATH. Re-running setup must reuse a complete checkout instead
# of calling git clone into the non-empty directory.
mkdir -p "$TMP_DIR/fzf-home/.local/share/blesh" "$TMP_DIR/fzf-home/.fzf" "$TMP_DIR/fzf-bin"
touch "$TMP_DIR/fzf-home/.local/share/blesh/ble.sh"
printf '#!/usr/bin/env bash\ntouch "$FZF_INSTALL_MARKER"\n' > "$TMP_DIR/fzf-home/.fzf/install"
printf '#!/usr/bin/env bash\nif [[ "$1" == "clone" ]]; then touch "$FZF_CLONE_MARKER"; exit 99; fi\nexit 0\n' > "$TMP_DIR/fzf-bin/git"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP_DIR/fzf-bin/zoxide"
chmod +x "$TMP_DIR/fzf-home/.fzf/install" "$TMP_DIR/fzf-bin/git" "$TMP_DIR/fzf-bin/zoxide"

FZF_INSTALL_MARKER="$TMP_DIR/fzf-install-called" FZF_CLONE_MARKER="$TMP_DIR/fzf-clone-called" PATH="$TMP_DIR/fzf-bin:$FAKE_BIN" HOME="$TMP_DIR/fzf-home" DEVTOOLS_CACHE_DIR="$TMP_DIR/cache" bash "$SETUP_SH" > "$TMP_DIR/fzf.log" 2>&1 ||
  fail "fzf retry failed; output: $(cat "$TMP_DIR/fzf.log")"
assert_file "$TMP_DIR/fzf-install-called"
[[ ! -e "$TMP_DIR/fzf-clone-called" ]] || fail "git clone was called for an existing fzf checkout"

# An incomplete checkout must be preserved and replaced with a fresh clone.
mkdir -p "$TMP_DIR/fzf-incomplete-home/.local/share/blesh" "$TMP_DIR/fzf-incomplete-home/.fzf" "$TMP_DIR/fzf-incomplete-bin"
touch "$TMP_DIR/fzf-incomplete-home/.local/share/blesh/ble.sh" "$TMP_DIR/fzf-incomplete-home/.fzf/partial-file"
printf '#!/usr/bin/env bash\nif [[ "$1" == "clone" ]]; then dest="${@: -1}"; if [[ -e "$dest" ]]; then touch "$FZF_CLONE_MARKER"; exit 99; fi; mkdir -p "$dest"; printf "#!/usr/bin/env bash\\ntouch \\\"$FZF_INSTALL_MARKER\\\"\\n" > "$dest/install"; chmod +x "$dest/install"; fi\nexit 0\n' > "$TMP_DIR/fzf-incomplete-bin/git"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP_DIR/fzf-incomplete-bin/zoxide"
chmod +x "$TMP_DIR/fzf-incomplete-bin/git" "$TMP_DIR/fzf-incomplete-bin/zoxide"

FZF_INSTALL_MARKER="$TMP_DIR/fzf-incomplete-install-called" FZF_CLONE_MARKER="$TMP_DIR/fzf-incomplete-clone-failed" PATH="$TMP_DIR/fzf-incomplete-bin:$FAKE_BIN" HOME="$TMP_DIR/fzf-incomplete-home" DEVTOOLS_CACHE_DIR="$TMP_DIR/cache" bash "$SETUP_SH" > "$TMP_DIR/fzf-incomplete.log" 2>&1 ||
  fail "incomplete fzf retry failed; output: $(cat "$TMP_DIR/fzf-incomplete.log")"
assert_file "$TMP_DIR/fzf-incomplete-install-called"
[[ ! -e "$TMP_DIR/fzf-incomplete-clone-failed" ]] || fail "incomplete fzf directory was not moved before cloning"
find "$TMP_DIR/fzf-incomplete-home" -maxdepth 1 -type d -name '.fzf.backup.*' | grep -q . || fail "incomplete fzf directory was not backed up"
fi

# --- shell/bash setup.sh plugin CLI ---
bash -n "$SETUP_SH" || fail "bash -n shell/bash/setup.sh"

cli_help="$TMP_DIR/bash-cli-help.log"
bash "$SETUP_SH" --help >"$cli_help" 2>&1 || fail "setup.sh --help failed"
assert_contains "$cli_help" "install"
assert_contains "$cli_help" "list"
assert_contains "$cli_help" "-n"
assert_not_contains "$cli_help" "-d, --dry-run"

cli_list_home="$TMP_DIR/bash-list-home"
mkdir -p "$cli_list_home/.local/share/blesh" "$cli_list_home/.local/bin"
if [[ "$DEVTOOLS_TEST_PROFILE" == "macos" ]]; then
  mkdir -p "$cli_list_home/homebrew/share/blesh"
  touch "$cli_list_home/homebrew/share/blesh/ble.sh"
  cat >"$cli_list_home/.local/bin/brew" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--prefix" ]]; then
  printf '%s\n' "$HOME/homebrew"
  exit 0
fi
exit 0
EOF
  chmod +x "$cli_list_home/.local/bin/brew"
else
  touch "$cli_list_home/.local/share/blesh/ble.sh"
fi
printf '#!/usr/bin/env bash\nexit 0\n' > "$cli_list_home/.local/bin/zoxide"
chmod +x "$cli_list_home/.local/bin/zoxide"
# fzf and starship intentionally missing
cli_list="$TMP_DIR/bash-cli-list.log"
PATH="$cli_list_home/.local/bin:$FAKE_BIN" HOME="$cli_list_home" \
  bash "$SETUP_SH" list >"$cli_list" 2>&1 ||
  fail "setup.sh list failed: $(cat "$cli_list")"
assert_contains "$cli_list" "blesh"
assert_contains "$cli_list" "zoxide"
assert_contains "$cli_list" "fzf"
assert_contains "$cli_list" "starship"
assert_contains "$cli_list" "[installed]"
assert_contains "$cli_list" "[missing]"
grep -E 'blesh[[:space:]].*\[installed\]' "$cli_list" >/dev/null ||
  fail "blesh should be installed in list output"
grep -E 'zoxide[[:space:]].*\[installed\]' "$cli_list" >/dev/null ||
  fail "zoxide should be installed in list output"
grep -E 'fzf[[:space:]].*\[missing\]' "$cli_list" >/dev/null ||
  fail "fzf should be missing in list output"
grep -E 'starship[[:space:]].*\[missing\]' "$cli_list" >/dev/null ||
  fail "starship should be missing in list output"

cli_unknown_rc=0
bash "$SETUP_SH" install nope >"$TMP_DIR/bash-cli-unknown.log" 2>&1 || cli_unknown_rc=$?
[[ "$cli_unknown_rc" -ne 0 ]] || fail "unknown plugin should fail"
assert_contains "$TMP_DIR/bash-cli-unknown.log" "list"

cli_dry="$TMP_DIR/bash-cli-dry.log"
HOME="$TMP_DIR/bash-dry-home" mkdir -p "$TMP_DIR/bash-dry-home"
HOME="$TMP_DIR/bash-dry-home" PATH="$FAKE_BIN" \
  bash "$SETUP_SH" install -n >"$cli_dry" 2>&1 ||
  fail "setup.sh install -n failed: $(cat "$cli_dry")"
assert_contains "$cli_dry" "试运行"
assert_contains "$cli_dry" "bleopt exec_elapsed_mark="
[[ ! -f "$TMP_DIR/bash-dry-home/.bashrc" ]] ||
  fail "dry-run must not create .bashrc when it did not exist"
[[ ! -f "$TMP_DIR/bash-dry-home/.blerc" ]] ||
  fail "dry-run must not create .blerc when it did not exist"

if [[ "$DEVTOOLS_TEST_PROFILE" != "macos" ]]; then
# install fzf only must not invoke zoxide online installer (curl) when zoxide missing
single_home="$TMP_DIR/bash-single-home"
single_bin="$TMP_DIR/bash-single-bin"
mkdir -p "$single_home/.local/share/blesh" "$single_home/.fzf" "$single_bin"
touch "$single_home/.local/share/blesh/ble.sh"
printf '#!/usr/bin/env bash\ntouch "$FZF_INSTALL_MARKER"\n' > "$single_home/.fzf/install"
chmod +x "$single_home/.fzf/install"
printf '#!/usr/bin/env bash\nif [[ "$1" == "clone" ]]; then touch "$FZF_CLONE_MARKER"; exit 99; fi\nexit 0\n' > "$single_bin/git"
cat > "$single_bin/curl" <<'EOF'
#!/usr/bin/env bash
touch "$CURL_CALLED_MARKER"
exit 97
EOF
chmod +x "$single_bin/git" "$single_bin/curl"

FZF_INSTALL_MARKER="$TMP_DIR/bash-single-fzf-install" \
FZF_CLONE_MARKER="$TMP_DIR/bash-single-fzf-clone" \
CURL_CALLED_MARKER="$TMP_DIR/bash-single-curl" \
PATH="$single_bin:$FAKE_BIN" HOME="$single_home" DEVTOOLS_CACHE_DIR="$TMP_DIR/cache" \
  bash "$SETUP_SH" install fzf >"$TMP_DIR/bash-single.log" 2>&1 ||
  fail "install fzf failed: $(cat "$TMP_DIR/bash-single.log")"
assert_file "$TMP_DIR/bash-single-fzf-install"
[[ ! -e "$TMP_DIR/bash-single-curl" ]] || fail "install fzf must not curl-install zoxide/starship"
assert_contains "$single_home/.bashrc" "Lightweight Bash Plugins"
# ls color fallback (see README Issues 2026-11-16): Ghostty's TERM does not
# match /etc/DIR_COLORS.* TERM lines, so the system colorls.sh skips its aliases.
assert_contains "$single_home/.bashrc" "alias ls='ls --color=auto'"
assert_contains "$single_home/.bashrc" "alias ll='ls -l --color=auto'"
assert_contains "$single_home/.bashrc" "alias la='ls -A --color=auto'"
assert_contains "$single_home/.bashrc" "alias l.='ls -d .* --color=auto'"

managed_block="$TMP_DIR/bash-managed-block.sh"
awk '/^# === Lightweight Bash Plugins \(devtools\) ===$/{in_block=1} in_block{print} /^# === End Lightweight Bash Plugins \(devtools\) ===$/{in_block=0}' \
  "$single_home/.bashrc" > "$managed_block"
ls_color_home="$TMP_DIR/bash-ls-color-home"
mkdir -p "$ls_color_home"
HOME="$ls_color_home" TERM=xterm-ghostty LS_COLORS= \
  bash --noprofile --norc -c '
    source "$1"
    alias ls
    if [[ -n "${LS_COLORS:-}" ]]; then echo "LS_COLORS_SET"; fi
  ' _ "$managed_block" > "$TMP_DIR/bash-ls-color.log" 2>&1 ||
  fail "sourcing managed block under TERM=xterm-ghostty failed: $(cat "$TMP_DIR/bash-ls-color.log")"
assert_contains "$TMP_DIR/bash-ls-color.log" "alias ls='ls --color=auto'"
assert_contains "$TMP_DIR/bash-ls-color.log" "LS_COLORS_SET"
assert_file "$single_home/.blerc"
assert_contains "$single_home/.blerc" "bleopt exec_elapsed_mark="
assert_contains "$single_home/.blerc" "bleopt exec_errexit_mark="
assert_contains "$single_home/.blerc" "bleopt exec_exit_mark="
# starship.toml must NOT be written for fzf-only install
[[ ! -f "$single_home/.config/starship.toml" ]] ||
  fail "fzf-only install must not write starship.toml"

# Re-running must replace the managed blerc block and keep user content outside markers.
printf '%s\n' \
  "# user custom blerc" \
  "bleopt prompt_eol_mark=custom" \
  "# === Lightweight Bash Plugins (devtools) ===" \
  "bleopt exec_elapsed_mark=stale" \
  "# === End Lightweight Bash Plugins ===" \
  "# after block" > "$single_home/.blerc"
FZF_INSTALL_MARKER="$TMP_DIR/bash-blerc-idempotent-fzf" \
PATH="$single_bin:$FAKE_BIN" HOME="$single_home" DEVTOOLS_CACHE_DIR="$TMP_DIR/cache" \
  bash "$SETUP_SH" install fzf >"$TMP_DIR/bash-blerc-idempotent.log" 2>&1 ||
  fail "blerc idempotent reinstall failed: $(cat "$TMP_DIR/bash-blerc-idempotent.log")"
assert_contains "$single_home/.blerc" "# user custom blerc"
assert_contains "$single_home/.blerc" "bleopt prompt_eol_mark=custom"
assert_contains "$single_home/.blerc" "# after block"
assert_contains "$single_home/.blerc" "bleopt exec_elapsed_mark="
assert_not_contains "$single_home/.blerc" "bleopt exec_elapsed_mark=stale"
blerc_block_count="$(grep -cF '# === Lightweight Bash Plugins (devtools) ===' "$single_home/.blerc" || true)"
[[ "$blerc_block_count" -eq 1 ]] ||
  fail "expected exactly one managed blerc block, got $blerc_block_count"

# alias ble.sh
alias_rc=0
PATH="$single_bin:$FAKE_BIN" HOME="$single_home" DEVTOOLS_CACHE_DIR="$TMP_DIR/cache" \
  bash "$SETUP_SH" install ble.sh -n >"$TMP_DIR/bash-alias.log" 2>&1 || alias_rc=$?
[[ "$alias_rc" -eq 0 ]] || fail "ble.sh alias dry-run failed: $(cat "$TMP_DIR/bash-alias.log")"
fi

echo "PASS: Bash setup integration ($DEVTOOLS_TEST_PROFILE)"
