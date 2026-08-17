#!/usr/bin/env bash
# Regression: Cloudflare WARP yum repo must not use Alinux $releasever=4.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXIT_SETUP="${SCRIPT_DIR}/setup.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_file_contains() {
    local file="$1" expected="$2"
    grep -qF -- "$expected" "$file" \
        || fail "${file} should contain: ${expected}"
}

assert_file_not_contains() {
    local file="$1" unexpected="$2"
    if grep -qF -- "$unexpected" "$file"; then
        fail "${file} should not contain: ${unexpected}"
    fi
}

assert_eq() {
    local actual="$1" expected="$2" msg="$3"
    [[ "$actual" == "$expected" ]] || fail "${msg}: expected '${expected}', got '${actual}'"
}

echo "[1/5] source exit/setup.sh helpers without root/install side effects"
(
    export EXIT_SETUP_SOURCE_ONLY=true
    # shellcheck source=setup.sh
    source "$EXIT_SETUP"
    declare -F resolve_warp_rpm_releasever >/dev/null \
        || fail "resolve_warp_rpm_releasever should be defined"
    declare -F write_cloudflare_warp_repo >/dev/null \
        || fail "write_cloudflare_warp_repo should be defined"
    declare -F install_cloudflare_warp_rhel >/dev/null \
        || fail "install_cloudflare_warp_rhel should be defined"
    declare -F install_cloudflare_warp_rhel_cli_only >/dev/null \
        || fail "install_cloudflare_warp_rhel_cli_only should be defined"
)

echo "[2/5] Alinux/Anolis VERSION_ID maps to rpm/9 (el10 needs newer glibc)"
(
    export EXIT_SETUP_SOURCE_ONLY=true
    # shellcheck source=setup.sh
    source "$EXIT_SETUP"
    assert_eq "$(resolve_warp_rpm_releasever 4)" "9" "Alinux 4"
    assert_eq "$(resolve_warp_rpm_releasever 3)" "9" "Alinux 3"
    assert_eq "$(resolve_warp_rpm_releasever 8)" "9" "el8 fallback (rpm/8 unpublished)"
    assert_eq "$(resolve_warp_rpm_releasever 9)" "9" "RHEL 9"
    assert_eq "$(resolve_warp_rpm_releasever 10)" "10" "RHEL 10"
    assert_eq "$(resolve_warp_rpm_releasever "")" "9" "empty fallback"
)

echo "[3/5] write_cloudflare_warp_repo pins Alinux 4 to rpm/9 (not \$releasever)"
repo_file="${TMP_DIR}/cloudflare-warp.repo"
(
    export EXIT_SETUP_SOURCE_ONLY=true
    # shellcheck source=setup.sh
    source "$EXIT_SETUP"
    write_cloudflare_warp_repo "$repo_file" "4"
)
assert_file_contains "$repo_file" "baseurl=https://pkg.cloudflareclient.com/rpm/9"
assert_file_not_contains "$repo_file" '$releasever'
assert_file_not_contains "$repo_file" "/rpm/4"

echo "[4/5] rewriting an official broken repo is idempotent"
printf '%s\n' \
    '[cloudflare-warp-stable]' \
    'name=cloudflare-warp-stable' \
    'baseurl=https://pkg.cloudflareclient.com/rpm/$releasever' \
    'enabled=1' \
    >"$repo_file"
(
    export EXIT_SETUP_SOURCE_ONLY=true
    # shellcheck source=setup.sh
    source "$EXIT_SETUP"
    write_cloudflare_warp_repo "$repo_file" "4"
)
assert_file_contains "$repo_file" "baseurl=https://pkg.cloudflareclient.com/rpm/9"
assert_file_not_contains "$repo_file" '$releasever'

echo "[5/7] public IP detection does not fail when hostname is missing"
grep -q 'hostname -I 2>/dev/null' "$EXIT_SETUP" \
    || fail "SERVER_IP fallback should tolerate missing hostname"
grep -q 'awk '\''{print $1}'\'' || true' "$EXIT_SETUP" \
    || fail "hostname fallback must not fail under pipefail"
grep -q 'ip -4 addr show' "$EXIT_SETUP" \
    || fail "SERVER_IP should fall back to iproute when hostname is absent"

echo "[6/7] --skip-warp is documented and gates WARP install"
help_out="$("$EXIT_SETUP" --help)"
echo "$help_out" | grep -q -- '--skip-warp' \
    || fail "setup.sh --help should document --skip-warp"
grep -q 'SKIP_WARP' "$EXIT_SETUP" \
    || fail "setup.sh should define SKIP_WARP"
grep -q '已跳过 Cloudflare WARP' "$EXIT_SETUP" \
    || fail "setup.sh should skip WARP when --skip-warp is set"

echo "[7/7] missing webkit2gtk3 falls back to rpm --nodeps CLI-only install"
fake_bin="${TMP_DIR}/fake-bin"
mkdir -p "$fake_bin"
cat >"${fake_bin}/yum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "yum $*" >>"${FAKE_LOG}"
# Runtime dep install succeeds; cloudflare-warp itself fails like Alinux 4.
if [[ "$*" == *"cloudflare-warp"* ]]; then
    echo "nothing provides webkit2gtk3 needed by cloudflare-warp" >&2
    exit 1
fi
exit 0
EOF
cat >"${fake_bin}/dnf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "dnf $*" >>"${FAKE_LOG}"
# Support: dnf download --arch ARCH --destdir DIR cloudflare-warp
destdir=""
arch=""
prev=""
for arg in "$@"; do
    if [[ "$prev" == "--destdir" ]]; then
        destdir="$arg"
    elif [[ "$prev" == "--arch" ]]; then
        arch="$arg"
    fi
    prev="$arg"
done
if [[ "$1" == "download" && -n "$destdir" ]]; then
    : "${arch:=x86_64}"
    printf 'fake' >"${destdir}/cloudflare-warp-0:test-1.el9.${arch}.rpm"
    exit 0
fi
exit 0
EOF
cat >"${fake_bin}/rpm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "rpm $*" >>"${FAKE_LOG}"
exit 0
EOF
chmod +x "${fake_bin}/yum" "${fake_bin}/dnf" "${fake_bin}/rpm"
fake_log="${TMP_DIR}/pkg.log"
: >"$fake_log"
(
    export EXIT_SETUP_SOURCE_ONLY=true
    export PATH="${fake_bin}:/usr/bin:/bin"
    export FAKE_LOG="$fake_log"
    # shellcheck source=setup.sh
    source "$EXIT_SETUP"
    install_cloudflare_warp_rhel
)
grep -qF 'rpm -Uvh --nodeps' "$fake_log" \
    || fail "expected rpm --nodeps fallback when yum cannot satisfy webkit2gtk3; log=$(cat "$fake_log")"
grep -qF 'cloudflare-warp' "$fake_log" \
    || fail "expected cloudflare-warp package operations in fake log"

echo "PASS: exit/setup WARP yum repo regression checks"
