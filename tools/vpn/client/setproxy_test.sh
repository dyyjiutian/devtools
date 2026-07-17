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
echo "${FAKE_UNAME:-Darwin}"
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

cat >"${FAKE_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "context" && "${2:-}" == "show" ]]; then
    printf '%s\n' "${FAKE_DOCKER_CONTEXT:-default}"
fi
exit 0
EOF

cat >"${FAKE_BIN}/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF

cat >"${FAKE_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${SYSTEMCTL_LOG:?}"
EOF

cat >"${FAKE_BIN}/colima" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    status)
        [[ -n "${FAKE_COLIMA_STATUS:-}" ]] || exit 1
        printf '%s\n' "${FAKE_COLIMA_STATUS}"
        ;;
    ssh)
        shift
        [[ "${1:-}" == "--" ]] && shift
        [[ "${1:-}" == "sudo" ]] && shift
        case "${1:-}" in
            cat) cat "${COLIMA_DAEMON_JSON:?}" ;;
            tee) cat >"${COLIMA_DAEMON_JSON:?}" ;;
            *) exit 1 ;;
        esac
        ;;
    *) exit 1 ;;
esac
EOF

chmod +x "${FAKE_BIN}/uname" "${FAKE_BIN}/lsof" "${FAKE_BIN}/nc" "${FAKE_BIN}/curl" \
    "${FAKE_BIN}/docker" "${FAKE_BIN}/sudo" "${FAKE_BIN}/systemctl" "${FAKE_BIN}/colima"

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

printf '[6/8] test --size controls both speed downloads\n'
: >"${CURL_LOG}"
env -i \
    HOME="${HOME_ON}" \
    PATH="${FAKE_BIN}:/usr/bin:/bin" \
    CURL_LOG="${CURL_LOG}" \
    HTTP_PROXY="http://127.0.0.1:9999" \
    ALL_PROXY="socks5h://127.0.0.1:9998" \
    VPN_HTTP_PORT=8001 \
    VPN_SOCKS_PORT=1081 \
    "${SETPROXY}" test --size 2 >/dev/null 2>&1
baidu_call="$(grep 'www.baidu.com' "${CURL_LOG}" || true)"
tuna_call="$(grep 'mirrors.tuna.tsinghua.edu.cn/archlinux/iso/latest/archlinux-x86_64.iso' "${CURL_LOG}" || true)"
cloudflare_call="$(grep 'speed.cloudflare.com/__down?bytes=2000000' "${CURL_LOG}" || true)"
[[ "${baidu_call}" == *'<--proxy><><--noproxy><*>'* ]] \
    || fail "Baidu direct test did not explicitly bypass proxies"
[[ "${tuna_call}" == *'<--proxy><><--noproxy><*>'* ]] \
    || fail "domestic TUNA speed test did not explicitly bypass proxies"
[[ "${tuna_call}" == *'<-H><Range: bytes=0-1999999>'* ]] \
    || fail "domestic TUNA speed test ignored --size"
[[ "${cloudflare_call}" == *'<-x><socks5h://127.0.0.1:1081>'* ]] \
    || fail "overseas speed test did not use Cloudflare 10 MB through SOCKS"
if env -i HOME="${HOME_ON}" PATH="${FAKE_BIN}:/usr/bin:/bin" \
    "${SETPROXY}" test --size 0 >/dev/null 2>&1; then
    fail "setproxy test accepted an invalid --size"
fi
if grep -q 'mirrors.aliyun.com/centos' "${CURL_LOG}"; then
    fail "domestic speed test still uses the small Aliyun torrent"
fi
if grep -q 'proof.ovh.net' "${CURL_LOG}"; then
    fail "overseas speed test still uses OVH"
fi

printf '[7/9] Docker daemon proxy is merged, restored, and never restarted\n'
DOCKER_DAEMON_JSON="${TMP_ROOT}/linux-daemon.json"
cat >"${DOCKER_DAEMON_JSON}" <<'EOF'
{"log-driver":"json-file","proxies":{"http-proxy":"http://old-proxy:8080"}}
EOF
HOME_DOCKER="${TMP_ROOT}/home-docker"
SYSTEMCTL_LOG="${TMP_ROOT}/systemctl.log"
mkdir -p "${HOME_DOCKER}"
: >"${SYSTEMCTL_LOG}"
env -i \
    HOME="${HOME_DOCKER}" \
    PATH="${FAKE_BIN}:/usr/bin:/bin" \
    FAKE_UNAME=Linux \
    VPN_DOCKER_DAEMON_JSON="${DOCKER_DAEMON_JSON}" \
    SYSTEMCTL_LOG="${SYSTEMCTL_LOG}" \
    "${SETPROXY}" off >/dev/null 2>&1
assert_file_contains "${DOCKER_DAEMON_JSON}" '"http-proxy":"http://old-proxy:8080"'
env -i \
    HOME="${HOME_DOCKER}" \
    PATH="${FAKE_BIN}:/usr/bin:/bin" \
    FAKE_UNAME=Linux \
    VPN_DOCKER_DAEMON_JSON="${DOCKER_DAEMON_JSON}" \
    SYSTEMCTL_LOG="${SYSTEMCTL_LOG}" \
    "${SETPROXY}" on --http-port 8001 >"${TMP_ROOT}/docker-on.stdout" 2>"${TMP_ROOT}/docker-on.stderr"
assert_file_contains "${DOCKER_DAEMON_JSON}" '"log-driver"'
assert_file_contains "${DOCKER_DAEMON_JSON}" '"http-proxy": "http://127.0.0.1:8001"'
assert_file_contains "${TMP_ROOT}/docker-on.stdout" 'sudo systemctl restart docker'
env -i \
    HOME="${HOME_DOCKER}" \
    PATH="${FAKE_BIN}:/usr/bin:/bin" \
    FAKE_UNAME=Linux \
    VPN_DOCKER_DAEMON_JSON="${DOCKER_DAEMON_JSON}" \
    SYSTEMCTL_LOG="${SYSTEMCTL_LOG}" \
    "${SETPROXY}" off >"${TMP_ROOT}/docker-off.stdout" 2>"${TMP_ROOT}/docker-off.stderr"
assert_file_contains "${DOCKER_DAEMON_JSON}" '"http-proxy": "http://old-proxy:8080"'
if [[ -s "${SYSTEMCTL_LOG}" ]]; then
    fail "setproxy automatically restarted Docker"
fi

printf '[8/9] Colima uses the host gateway and Docker Desktop is skipped\n'
COLIMA_DAEMON_JSON="${TMP_ROOT}/colima-daemon.json"
printf '{"features":{"buildkit":true}}\n' >"${COLIMA_DAEMON_JSON}"
HOME_COLIMA="${TMP_ROOT}/home-colima"
mkdir -p "${HOME_COLIMA}"
env -i \
    HOME="${HOME_COLIMA}" \
    PATH="${FAKE_BIN}:/usr/bin:/bin" \
    FAKE_UNAME=Darwin \
    FAKE_COLIMA_STATUS='runtime: docker' \
    COLIMA_DAEMON_JSON="${COLIMA_DAEMON_JSON}" \
    "${SETPROXY}" on --http-port 8001 >"${TMP_ROOT}/colima-on.stdout" 2>"${TMP_ROOT}/colima-on.stderr"
assert_file_contains "${COLIMA_DAEMON_JSON}" '"http-proxy": "http://host.lima.internal:8001"'
assert_file_contains "${TMP_ROOT}/colima-on.stdout" 'colima restart'
env -i \
    HOME="${TMP_ROOT}/home-desktop" \
    PATH="${FAKE_BIN}:/usr/bin:/bin" \
    FAKE_UNAME=Darwin \
    FAKE_DOCKER_CONTEXT=desktop-linux \
    "${SETPROXY}" on --http-port 8001 >"${TMP_ROOT}/desktop.stdout" 2>"${TMP_ROOT}/desktop.stderr"
assert_file_contains "${TMP_ROOT}/desktop.stderr" 'Docker Desktop'

printf '[9/9] installer and complete uninstall lifecycle\n'
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
[[ -x "${HOME_INSTALL}/.local/bin/speed_test" ]] || fail "installer did not install speed_test executable"
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
[[ ! -e "${HOME_INSTALL}/.local/bin/speed_test" ]] || fail "uninstall left speed_test executable"
[[ ! -e "${HOME_INSTALL}/.config/vpn/proxy.env" ]] || fail "uninstall left proxy.env"
[[ ! -e "${HOME_INSTALL}/.config/vpn/setproxy.conf" ]] || fail "uninstall left setproxy.conf"
if grep -qE 'devtools setproxy PATH|vpn-shell-proxy managed' "${HOME_INSTALL}/.zshrc"; then
    fail "uninstall left managed zshrc blocks"
fi

printf 'PASS: setproxy regression checks\n'
