#!/usr/bin/env bash
# Rust installer CLI / dry-run suite (fake OS profile).
set -euo pipefail

SETUP_SH="$MODULE_ROOT/setup.sh"

test_help() {
  local out
  out="$(bash "$SETUP_SH" --help 2>&1)"
  assert_contains "$out" "dry-run" "rust setup --help mentions dry-run"
  assert_contains "$out" "--skip-cargo-tools" "rust setup --help mentions skip-cargo-tools"
  pass "rust setup --help ($DEVTOOLS_TEST_PROFILE)"
}

test_unknown_flag() {
  local rc=0
  bash "$SETUP_SH" --not-a-real-flag >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "unknown flag should exit 1"
  pass "rust setup unknown flag ($DEVTOOLS_TEST_PROFILE)"
}

test_dry_run() {
  local out
  out="$(bash "$SETUP_SH" --dry-run --skip-cargo-tools 2>&1)" || {
    echo "FAIL: rust setup --dry-run failed: $out" >&2
    return 1
  }
  assert_contains "$out" "DRY-RUN" "rust dry-run announces preview mode"
  pass "rust setup --dry-run ($DEVTOOLS_TEST_PROFILE)"
}

test_cargo_env_nounset() {
  local setup ops
  setup="$(cat "$SETUP_SH")"
  ops="$(cat "$MODULE_ROOT/tests/e2e/rust_ops_suite.sh")"
  assert_contains "$setup" "source_cargo_env" "rust setup sources cargo env via a helper"
  assert_contains "$setup" "set +u" "rust setup disables nounset around cargo env"
  assert_contains "$ops" "set +u" "rust E2E sources cargo env without nounset"
  pass "rust cargo env nounset guards ($DEVTOOLS_TEST_PROFILE)"
}

# Fake rustup for a machine where rustup is preinstalled (runner image / brew)
# but the cargo proxies do not exist yet. `default stable` creates them, which
# is what setup.sh must trigger; `show active-toolchain` only succeeds after a
# default toolchain has been set.
_write_fake_rustup() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/rustup" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
cargo_home="${CARGO_HOME:-$HOME/.cargo}"
case "${1:-}" in
  --version) echo "rustup 1.29.2 (fake)" ;;
  show) [[ -f "$cargo_home/.default-set" ]] || exit 1 ;;
  default)
    mkdir -p "$cargo_home/bin"
    printf '#!/usr/bin/env bash\necho "rustc 1.100.0 (fake)"\n' > "$cargo_home/bin/rustc"
    printf '#!/usr/bin/env bash\necho "cargo 1.100.0 (fake)"\n' > "$cargo_home/bin/cargo"
    chmod +x "$cargo_home/bin/rustc" "$cargo_home/bin/cargo"
    : > "$cargo_home/.default-set"
    : > "${RUSTUP_DEFAULT_MARKER:?}"
    ;;
  *) exit 0 ;;
esac
FAKE
  chmod +x "$bin/rustup"
}

_write_fake_proxy() {
  local path="$1" name="$2"
  printf '#!/usr/bin/env bash\necho "%s 1.100.0 (fake)"\n' "$name" > "$path"
  chmod +x "$path"
}

# Models the macos-26 runner: stable is already the default toolchain, so
# `rustup default stable` exits 0 WITHOUT writing proxies into a fresh
# CARGO_HOME. Only `rustup which <tool>` can locate the real binaries.
_write_fake_rustup_noop_default() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/rustup" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version) echo "rustup 1.29.2 (fake)" ;;
  show) exit 0 ;;
  default) exit 0 ;;
  which)
    tool="${2:-}"
    [[ -x "${FAKE_TOOLCHAIN_BIN:?}/$tool" ]] || exit 1
    echo "${FAKE_TOOLCHAIN_BIN}/$tool"
    ;;
  *) exit 0 ;;
esac
FAKE
  chmod +x "$bin/rustup"
}

test_preinstalled_rustup_noop_default() {
  local home out toolchain
  home="$(mktemp -d "${TMPDIR:-/tmp}/rust-noop.XXXXXX")"
  _write_fake_rustup_noop_default "$home/bin"
  toolchain="$home/.rustup/toolchains/stable-aarch64-apple-darwin/bin"
  mkdir -p "$toolchain"
  _write_fake_proxy "$toolchain/rustc" rustc
  _write_fake_proxy "$toolchain/cargo" cargo

  out="$home/setup.log"
  if ! FAKE_TOOLCHAIN_BIN="$toolchain" PATH="$home/bin:$PATH" HOME="$home" \
      bash "$SETUP_SH" --skip-cargo-tools >"$out" 2>&1; then
    echo "FAIL: setup with no-op rustup default failed: $(cat "$out")" >&2
    rm -rf "$home"
    return 1
  fi

  assert_file_exists "$home/.cargo/bin/rustc" \
    "rustc must be linked when rustup default writes no proxies"
  assert_contains "$(cat "$out")" "已补建工具链链接" \
    "setup must report the proxy fallback"
  assert_contains "$("$home/.cargo/bin/rustc" --version 2>&1)" "rustc" \
    "the linked rustc must actually run"
  assert_contains "$(readlink "$home/.cargo/bin/rustc")" "$toolchain/rustc" \
    "rustc must point at the toolchain binary"
  rm -rf "$home"
  pass "rust no-op rustup default gets toolchain links ($DEVTOOLS_TEST_PROFILE)"
}

test_preinstalled_rustup_missing_proxies() {
  local home out
  home="$(mktemp -d "${TMPDIR:-/tmp}/rust-preinstalled.XXXXXX")"
  _write_fake_rustup "$home/bin"
  mkdir -p "$home/.rustup"

  out="$home/setup.log"
  if ! RUSTUP_DEFAULT_MARKER="$home/default-called" PATH="$home/bin:$PATH" HOME="$home" \
      bash "$SETUP_SH" --skip-cargo-tools >"$out" 2>&1; then
    echo "FAIL: setup with preinstalled rustup failed: $(cat "$out")" >&2
    rm -rf "$home"
    return 1
  fi

  assert_file_exists "$home/default-called" \
    "rustup default stable must run when cargo proxies are missing"
  assert_file_exists "$home/.cargo/bin/rustc" "rustc proxy must exist after setup"
  assert_file_exists "$home/.cargo/env" "cargo env file must exist after setup"
  assert_contains "$(cat "$home/.bashrc")" "Rust/Cargo env" "rc block must be written"
  rm -rf "$home"
  pass "rust preinstalled rustup gets proxies ($DEVTOOLS_TEST_PROFILE)"
}

test_preinstalled_rustup_healthy() {
  local home out
  home="$(mktemp -d "${TMPDIR:-/tmp}/rust-healthy.XXXXXX")"
  _write_fake_rustup "$home/bin"
  mkdir -p "$home/.rustup" "$home/.cargo/bin"
  _write_fake_proxy "$home/.cargo/bin/rustc" rustc
  _write_fake_proxy "$home/.cargo/bin/cargo" cargo
  : > "$home/.cargo/.default-set"
  printf '# existing env\n' > "$home/.cargo/env"

  out="$home/setup.log"
  if ! RUSTUP_DEFAULT_MARKER="$home/default-called" PATH="$home/bin:$PATH" HOME="$home" \
      bash "$SETUP_SH" --skip-cargo-tools >"$out" 2>&1; then
    echo "FAIL: setup with healthy rustup failed: $(cat "$out")" >&2
    rm -rf "$home"
    return 1
  fi

  if [[ -e "$home/default-called" ]]; then
    echo "FAIL: a healthy install must not re-run rustup default" >&2
    rm -rf "$home"
    return 1
  fi
  assert_contains "$(cat "$home/.cargo/env")" "# existing env" \
    "an existing cargo env file must be preserved"
  rm -rf "$home"
  pass "rust healthy preinstalled rustup left alone ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_unknown_flag
test_dry_run
test_cargo_env_nounset
test_preinstalled_rustup_missing_proxies
test_preinstalled_rustup_noop_default
test_preinstalled_rustup_healthy
echo "PASS: rust suite complete ($DEVTOOLS_TEST_PROFILE)"
