#!/usr/bin/env bash
# Regression tests for standalone setproxy and its installer.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETPROXY="${SCRIPT_DIR}/bin/setproxy"
INSTALLER="${SCRIPT_DIR}/install-setproxy.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/setproxy-test.XXXXXX")"
FAKE_BIN="${TMP_ROOT}/fake-bin"
CURL_LOG="${TMP_ROOT}/curl.log"

cleanup() {
    rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT INT TERM

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_file_contains() {
    local file="$1" expected="$2"
    grep -qF "${expected}" "${file}" || fail "${file} does not contain: ${expected}"
}

mkdir -p "${FAKE_BIN}"

cat >"${FAKE_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
echo Darwin
EOF

cat >"${FAKE_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *:8001*|*:1081*) exit 0 ;;
    *) exit 1 ;;
esac
EOF

cat >"${FAKE_BIN}/nc" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-h" ]]; then
    echo 'usage: nc -x proxy:port -X 5 host port'
fi
exit 0
EOF

cat >"${FAKE_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
{
    for arg in "$@"; do
        printf '<%s>' "$arg"
    done
    printf '\n'
} >>"${CURL_LOG:?}"

case "$*" in
    *speed_download*) printf '200 1.000000 1048576 1048576' ;;
    *) printf '200' ;;
esac
EOF

chmod +x "${FAKE_BIN}/uname" "${FAKE_BIN}/lsof" "${FAKE_BIN}/nc" "${FAKE_BIN}/curl"

printf '[1/7] shell syntax\n'
bash -n "${SETPROXY}" "${INSTALLER}"

printf '[2/7] macOS V2RayXS autodetection and clean on --emit\n'
HOME_ON="${TMP_ROOT}/home-on"
mkdir -p "${HOME_ON}"
touch "${HOME_ON}/.zshrc"
env -i \
    HOME="${HOME_ON}" \
    PATH="${FAKE_BIN}:/usr/bin:/bin" \
    CURL_LOG="${CURL_LOG}" \
    "${SETPROXY}" on --emit >"${TMP_ROOT}/on.stdout" 2>"${TMP_ROOT}/on.stderr"

if grep -Ev '^(export [A-Za-z_][A-Za-z0-9_]*=|$)' "${TMP_ROOT}/on.stdout" >/dev/null; then
    sed -n '1,120p' "${TMP_ROOT}/on.stdout" >&2
    fail "on --emit stdout contains non-export output"
fi
assert_file_contains "${TMP_ROOT}/on.stdout" 'export HTTP_PROXY="http://127.0.0.1:8001"'
assert_file_contains "${TMP_ROOT}/on.stdout" 'export ALL_PROXY="socks5h://127.0.0.1:1081"'
assert_file_contains "${TMP_ROOT}/on.stdout" 'export GIT_SSH_COMMAND='
assert_file_contains "${HOME_ON}/.config/vpn/setproxy.conf" 'HTTP_PORT="8001"'
assert_file_contains "${HOME_ON}/.config/vpn/setproxy.conf" 'SOCKS_PORT="1081"'

printf '[3/7] emitted Git SSH command uses SOCKS without SSH config changes\n'
(
    set +u
    eval "$(cat "${TMP_ROOT}/on.stdout")"
    [[ "${GIT_SSH_COMMAND:-}" == *'nc -x 127.0.0.1:1081 -X 5 %h %p'* ]] \
        || fail "GIT_SSH_COMMAND does not use V2RayXS SOCKS"
)
[[ ! -e "${HOME_ON}/.ssh/config" ]] || fail "setproxy created an SSH config"

printf '[4/7] clean off --emit\n'
env -i \
    HOME="${HOME_ON}" \
    PATH="${FAKE_BIN}:/usr/bin:/bin" \
    CURL_LOG="${CURL_LOG}" \
    "${SETPROXY}" off --emit >"${TMP_ROOT}/off.stdout" 2>"${TMP_ROOT}/off.stderr"
if grep -Ev '^(unset [A-Za-z_ ][A-Za-z0-9_ ]*|$)' "${TMP_ROOT}/off.stdout" >/dev/null; then
    sed -n '1,120p' "${TMP_ROOT}/off.stdout" >&2
    fail "off --emit stdout contains non-unset output"
fi
assert_file_contains "${TMP_ROOT}/off.stdout" 'GIT_SSH_COMMAND'
[[ ! -e "${HOME_ON}/.config/vpn/proxy.env" ]] || fail "off did not remove proxy.env"

printf '[5/7] command-line overrides and Git SSH opt-out\n'
HOME_OVERRIDE="${TMP_ROOT}/home-override"
mkdir -p "${HOME_OVERRIDE}"
env -i \
    HOME="${HOME_OVERRIDE}" \
    PATH="${FAKE_BIN}:/usr/bin:/bin" \
    CURL_LOG="${CURL_LOG}" \
    "${SETPROXY}" on --emit \
    --http-port 9001 --socks-port=9002 --no-git-ssh \
    >"${TMP_ROOT}/override.stdout" 2>"${TMP_ROOT}/override.stderr"
assert_file_contains "${TMP_ROOT}/override.stdout" 'export HTTP_PROXY="http://127.0.0.1:9001"'
assert_file_contains "${TMP_ROOT}/override.stdout" 'export ALL_PROXY="socks5h://127.0.0.1:9002"'
assert_file_contains "${TMP_ROOT}/override.stdout" 'unset GIT_SSH_COMMAND'

printf '[6/7] domestic test calls bypass inherited proxies\n'
: >"${CURL_LOG}"
env -i \
    HOME="${HOME_ON}" \
    PATH="${FAKE_BIN}:/usr/bin:/bin" \
    CURL_LOG="${CURL_LOG}" \
    HTTP_PROXY="http://127.0.0.1:9999" \
    ALL_PROXY="socks5h://127.0.0.1:9998" \
    VPN_HTTP_PORT=8001 \
    VPN_SOCKS_PORT=1081 \
    "${SETPROXY}" test >/dev/null 2>&1
baidu_call="$(grep 'www.baidu.com' "${CURL_LOG}" || true)"
aliyun_call="$(grep 'mirrors.aliyun.com' "${CURL_LOG}" || true)"
[[ "${baidu_call}" == *'<--proxy><><--noproxy><*>'* ]] \
    || fail "Baidu direct test did not explicitly bypass proxies"
[[ "${aliyun_call}" == *'<--proxy><><--noproxy><*>'* ]] \
    || fail "domestic speed test did not explicitly bypass proxies"

printf '[7/7] installer and complete uninstall lifecycle\n'
HOME_INSTALL="${TMP_ROOT}/home-install"
mkdir -p "${HOME_INSTALL}"
cat >"${HOME_INSTALL}/.zshrc" <<'EOF'
export PATH="$HOME/.local/bin:$PATH"
setproxy() { echo legacy; }
unsetproxy() { echo legacy; }
EOF
env -i HOME="${HOME_INSTALL}" SHELL=/bin/zsh PATH="/usr/bin:/bin" \
    bash "${INSTALLER}" >"${TMP_ROOT}/install.stdout" 2>"${TMP_ROOT}/install.stderr"
[[ -x "${HOME_INSTALL}/.local/bin/setproxy" ]] || fail "installer did not install executable"
assert_file_contains "${TMP_ROOT}/install.stderr" '已有 setproxy/unsetproxy'
if grep -qF '# >>> devtools setproxy PATH >>>' "${HOME_INSTALL}/.zshrc"; then
    fail "installer duplicated an existing ~/.local/bin PATH entry"
fi

env -i \
    HOME="${HOME_INSTALL}" \
    PATH="${FAKE_BIN}:/usr/bin:/bin" \
    CURL_LOG="${CURL_LOG}" \
    VPN_HTTP_PORT=8001 \
    VPN_SOCKS_PORT=1081 \
    "${HOME_INSTALL}/.local/bin/setproxy" on >/dev/null 2>&1

env -i HOME="${HOME_INSTALL}" SHELL=/bin/zsh PATH="/usr/bin:/bin" \
    bash "${INSTALLER}" --uninstall >/dev/null
[[ ! -e "${HOME_INSTALL}/.local/bin/setproxy" ]] || fail "uninstall left executable"
[[ ! -e "${HOME_INSTALL}/.config/vpn/proxy.env" ]] || fail "uninstall left proxy.env"
[[ ! -e "${HOME_INSTALL}/.config/vpn/setproxy.conf" ]] || fail "uninstall left setproxy.conf"
if grep -qE 'devtools setproxy PATH|vpn-shell-proxy managed' "${HOME_INSTALL}/.zshrc"; then
    fail "uninstall left managed zshrc blocks"
fi

printf 'PASS: setproxy regression checks\n'
