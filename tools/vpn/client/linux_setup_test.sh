#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINUX_SETUP="${SCRIPT_DIR}/linux_setup.sh"
TUN_ROUTE_HELPER="${SCRIPT_DIR}/bin/xray-tun-route"
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

assert_text_contains() {
    local text="$1" expected="$2"
    [[ "$text" == *"$expected"* ]] || fail "text should contain: ${expected}"
}

render_client_config() {
    local mode="$1" config_dir="$2"
    (
        set --
        [[ "$mode" == "tun" ]] && set -- --tun
        # shellcheck source=linux_setup.sh
        source "$LINUX_SETUP"
        XRAY_CONFIG_DIR="$config_dir"
        UUID="11111111-1111-1111-1111-111111111111"
        PUBLIC_KEY="test-public-key"
        SHORT_ID="1234abcd"
        RELAY_IP="203.0.113.10"
        write_client_config
    )
}

echo "[1/6] --tun is documented"
help_output="$(bash "$LINUX_SETUP" --help)"
[[ "$help_output" == *"--tun"* ]] || fail "linux_setup.sh --help should document --tun"

echo "[2/6] default and TUN client configurations"
normal_dir="${TMP_DIR}/normal"
tun_dir="${TMP_DIR}/tun"
mkdir -p "$normal_dir" "$tun_dir"
render_client_config normal "$normal_dir"
render_client_config tun "$tun_dir"

assert_file_not_contains "${normal_dir}/client.json" '"protocol": "tun"'
assert_file_not_contains "${normal_dir}/client.json" '"mark": 255'
assert_file_contains "${tun_dir}/client.json" '"protocol": "tun"'
assert_file_contains "${tun_dir}/client.json" '"name": "xray0"'
assert_file_contains "${tun_dir}/client.json" '"MTU": 1500'
assert_file_contains "${tun_dir}/client.json" '"mark": 255'
[[ "$(grep -cF '"mark": 255' "${tun_dir}/client.json")" -eq 2 ]] \
    || fail "TUN proxy and direct outbounds should both carry mark 255"
python3 -m json.tool "${normal_dir}/client.json" >/dev/null
python3 -m json.tool "${tun_dir}/client.json" >/dev/null

echo "[3/6] TUN policy routing helper"
fake_ip="${TMP_DIR}/ip"
ip_log="${TMP_DIR}/ip.log"
cat > "$fake_ip" <<'FAKE_IP'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$IP_LOG"
if [[ " $* " == *" rule delete "* ]]; then
    exit 2
fi
exit 0
FAKE_IP
chmod +x "$fake_ip"

IP_BIN="$fake_ip" IP_LOG="$ip_log" "$TUN_ROUTE_HELPER" up
IP_BIN="$fake_ip" IP_LOG="$ip_log" "$TUN_ROUTE_HELPER" up
IP_BIN="$fake_ip" IP_LOG="$ip_log" "$TUN_ROUTE_HELPER" status >/dev/null
IP_BIN="$fake_ip" IP_LOG="$ip_log" "$TUN_ROUTE_HELPER" down
IP_BIN="$fake_ip" IP_LOG="$ip_log" "$TUN_ROUTE_HELPER" down

assert_file_contains "$ip_log" '-4 route replace default dev xray0 table 1001'
assert_file_contains "$ip_log" '-4 rule add priority 10000 fwmark 255 lookup main'
assert_file_contains "$ip_log" '-4 rule add priority 10010 uidrange 0-4294967294 lookup 1001'
assert_file_contains "$ip_log" '-6 route replace default dev xray0 table 1001'
assert_file_contains "$ip_log" '-6 rule add priority 10000 fwmark 255 lookup main'
assert_file_contains "$ip_log" '-6 rule add priority 10010 uidrange 0-4294967294 lookup 1001'
assert_file_contains "$ip_log" '-4 route flush table 1001'
assert_file_contains "$ip_log" '-6 route flush table 1001'

echo "[4/6] normal and TUN systemd units"
normal_systemd_dir="${TMP_DIR}/systemd-normal"
tun_systemd_dir="${TMP_DIR}/systemd-tun"
mkdir -p "$normal_systemd_dir" "$tun_systemd_dir"
(
    set --
    # shellcheck source=linux_setup.sh
    source "$LINUX_SETUP"
    XRAY_SYSTEMD_DIR="$normal_systemd_dir"
    TUN_MODE=false
    write_systemd_service
)
(
    set -- --tun
    # shellcheck source=linux_setup.sh
    source "$LINUX_SETUP"
    XRAY_SYSTEMD_DIR="$tun_systemd_dir"
    XRAY_TUN_HELPER_PATH="/usr/local/libexec/xray-client-tun-route"
    write_systemd_service
    write_tun_routing_service
)

normal_unit="${normal_systemd_dir}/xray-client.service"
tun_unit="${tun_systemd_dir}/xray-client.service"
route_unit="${tun_systemd_dir}/xray-client-tun-routing.service"
assert_file_not_contains "$normal_unit" 'xray-client-tun-routing.service'
assert_file_contains "$tun_unit" 'Wants=xray-client-tun-routing.service'
assert_file_contains "$route_unit" 'After=xray-client.service'
assert_file_contains "$route_unit" 'Requires=xray-client.service'
assert_file_contains "$route_unit" 'BindsTo=xray-client.service'
assert_file_contains "$route_unit" 'ExecStart=/usr/local/libexec/xray-client-tun-route up'
assert_file_contains "$route_unit" 'ExecStop=/usr/local/libexec/xray-client-tun-route down'
assert_file_contains "$route_unit" 'RemainAfterExit=yes'

echo "[5/6] TUN support install and removal lifecycle"
lifecycle_systemd_dir="${TMP_DIR}/systemd-lifecycle"
lifecycle_helper="${TMP_DIR}/libexec/xray-client-tun-route"
systemctl_log="${TMP_DIR}/systemctl.log"
fake_bin="${TMP_DIR}/fake-bin"
mkdir -p "$lifecycle_systemd_dir" "$fake_bin"
cat > "${fake_bin}/systemctl" <<'FAKE_SYSTEMCTL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SYSTEMCTL_LOG"
exit 0
FAKE_SYSTEMCTL
chmod +x "${fake_bin}/systemctl"

(
    set -- --tun
    # shellcheck source=linux_setup.sh
    source "$LINUX_SETUP"
    XRAY_SYSTEMD_DIR="$lifecycle_systemd_dir"
    XRAY_TUN_HELPER_PATH="$lifecycle_helper"
    install_tun_routing
    [[ -x "$lifecycle_helper" ]] || fail "installed TUN helper should be executable"
    [[ -f "${lifecycle_systemd_dir}/xray-client-tun-routing.service" ]] \
        || fail "TUN routing unit should be installed"
    PATH="${fake_bin}:$PATH" IP_BIN="$fake_ip" IP_LOG="$ip_log" \
        SYSTEMCTL_LOG="$systemctl_log" remove_tun_routing
)

[[ ! -e "$lifecycle_helper" ]] || fail "TUN helper should be removed"
[[ ! -e "${lifecycle_systemd_dir}/xray-client-tun-routing.service" ]] \
    || fail "TUN routing unit should be removed"
assert_file_contains "$systemctl_log" 'stop xray-client-tun-routing.service'
assert_file_contains "$systemctl_log" 'disable xray-client-tun-routing.service'

echo "[6/6] install, status, and clean wire the TUN lifecycle"
(
    set --
    # shellcheck source=linux_setup.sh
    source "$LINUX_SETUP"
    assert_text_contains "$(declare -f do_install)" 'remove_tun_routing'
    assert_text_contains "$(declare -f do_install)" 'install_tun_routing'
    assert_text_contains "$(declare -f do_status)" 'xray-client-tun-routing.service'
    assert_text_contains "$(declare -f do_status)" 'xray-tun-route'
    assert_text_contains "$(declare -f do_clean)" 'remove_tun_routing'
)

echo "PASS: linux_setup TUN regression checks"
