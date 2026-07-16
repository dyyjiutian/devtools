#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_contains() {
  local file="$1" expected="$2"
  grep -Fq "$expected" "$file" || fail "expected '$expected' in $file"
}

assert_not_contains() {
  local file="$1" unexpected="$2"
  ! grep -Fq "$unexpected" "$file" || fail "did not expect '$unexpected' in $file"
}

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

CURL_FAILURE_MARKER="$TMP_DIR/curl-called" PATH="$TMP_DIR/bin:/usr/bin:/bin" HOME="$TMP_DIR/home" DEVTOOLS_CACHE_DIR="$TMP_DIR/cache" bash "$ROOT/terminal/bash/setup.sh" > "$TMP_DIR/starship.log" 2>&1 ||
  fail "Starship cache install failed; output: $(cat "$TMP_DIR/starship.log")"
assert_file "$TMP_DIR/home/.local/bin/starship"
[[ ! -e "$TMP_DIR/curl-called" ]] || fail "online installer was called despite a valid cache"

# Repository rendering must map Alibaba Cloud Linux 4 to an explicit compatible
# CentOS repository version and retain $releasever for normal CentOS.
cat > "$TMP_DIR/docker-ce.repo" <<'EOF'
[docker-ce-stable]
baseurl=https://download.docker.com/linux/centos/$releasever/$basearch/stable
EOF
cat > "$TMP_DIR/alinux-release" <<'EOF'
ID=alinux
VERSION_ID=4
EOF
cat > "$TMP_DIR/centos-release" <<'EOF'
ID=centos
VERSION_ID=9
EOF

SETUP_CENTOS_NO_MAIN=1 OS_RELEASE_FILE="$TMP_DIR/alinux-release" DEVTOOLS_CACHE_DIR="$TMP_DIR/cache" bash -c '
  source "$1"
  render_docker_repo "$2" "$3"
' _ "$ROOT/os/linux/setup_centos.sh" "$TMP_DIR/docker-ce.repo" "$TMP_DIR/alinux.repo" ||
  fail "Alibaba Cloud Linux repo rendering failed"
assert_contains "$TMP_DIR/alinux.repo" "http"
assert_contains "$TMP_DIR/alinux.repo" "/centos/9/"
assert_not_contains "$TMP_DIR/alinux.repo" '$releasever'
assert_not_contains "$TMP_DIR/alinux.repo" "/centos/4"

SETUP_CENTOS_NO_MAIN=1 OS_RELEASE_FILE="$TMP_DIR/centos-release" DEVTOOLS_CACHE_DIR="$TMP_DIR/cache" bash -c '
  source "$1"
  render_docker_repo "$2" "$3"
' _ "$ROOT/os/linux/setup_centos.sh" "$TMP_DIR/docker-ce.repo" "$TMP_DIR/centos.repo" ||
  fail "CentOS repo rendering failed"
assert_contains "$TMP_DIR/centos.repo" '$releasever'

# The cached NodeSource script must not reject Alibaba Cloud Linux solely
# because /etc/redhat-release is absent.
assert_not_contains "$ROOT/cache/scripts/nodesource-setup-20.x" '! [ -f /etc/redhat-release ] && ! grep -q "Amazon Linux" /etc/system-release'
assert_contains "$ROOT/cache/scripts/nodesource-setup-20.x" 'command -v rpm'

echo "PASS: Linux setup cache and ECS repository regression tests"
