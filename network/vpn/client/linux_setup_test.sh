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
        export LINUX_SETUP_SOURCE_ONLY=true
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

echo "[1/9] --tun is documented"
help_output="$(bash "$LINUX_SETUP" --help)"
[[ "$help_output" == *"--tun"* ]] || fail "linux_setup.sh --help should document --tun"

echo "[2/9] sourcing proxy on still updates the current shell"
source_home="${TMP_DIR}/source-home"
mkdir -p "$source_home"
if ! env -i HOME="$source_home" PATH="/usr/bin:/bin" \
    VPN_HTTP_PORT=18009 VPN_SOCKS_PORT=18008 \
    bash -c 'set -euo pipefail; setup=$1; set -- proxy on; source "$setup" >/dev/null; [[ "${HTTP_PROXY:-}" == "http://127.0.0.1:18009" ]]' \
    bash "$LINUX_SETUP"; then
    fail "source linux_setup.sh proxy on should update the current shell"
fi

echo "[3/9] default and TUN client configurations"
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

echo "[4/9] TUN policy routing helper"
fake_ip="${TMP_DIR}/ip"
ip_log="${TMP_DIR}/ip.log"
fake_sysctl="${TMP_DIR}/sysctl"
sysctl_log="${TMP_DIR}/sysctl.log"
sysctl_state_dir="${TMP_DIR}/sysctl-state"
tun_state_file="${TMP_DIR}/xray-tun.state"
tun_uid_state_file="${TMP_DIR}/xray-tun.uid"
mkdir -p "$sysctl_state_dir"
printf '1\n' > "${sysctl_state_dir}/all"
printf '1\n' > "${sysctl_state_dir}/iface"
cat > "$fake_ip" <<'FAKE_IP'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${ORDER_LOG:-$IP_LOG}"
if [[ " $* " == *" link show dev xray0 "* && -n "${FAKE_IP_LINK_FAILURES:-}" ]]; then
    count=0
    [[ -f "$FAKE_IP_COUNT_FILE" ]] && read -r count < "$FAKE_IP_COUNT_FILE"
    count=$((count + 1))
    printf '%s\n' "$count" > "$FAKE_IP_COUNT_FILE"
    ((count > FAKE_IP_LINK_FAILURES)) || exit 1
fi
if [[ " $* " == *" rule delete "* ]]; then
    exit 2
fi
if [[ " $* " == *" rule show "* && "${FAKE_IP_RULE_CONFLICT:-false}" == "true" ]]; then
    echo '10010: from all lookup main'
fi
exit 0
FAKE_IP
chmod +x "$fake_ip"
cat > "$fake_sysctl" <<'FAKE_SYSCTL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SYSCTL_LOG"
if [[ "${1:-}" == "-n" ]]; then
    if [[ "$2" == "net.ipv4.conf.all.rp_filter" ]]; then
        cat "${FAKE_SYSCTL_STATE_DIR}/all"
    else
        cat "${FAKE_SYSCTL_STATE_DIR}/iface"
    fi
    exit 0
fi
[[ "${1:-}" == "-q" ]] && shift
if [[ "${1:-}" == "-w" ]]; then
    assignment="$2"
    value="${assignment#*=}"
    if [[ "$assignment" == net.ipv4.conf.xray0.rp_filter=* \
        && "${FAKE_SYSCTL_FAIL_IFACE:-false}" == "true" ]]; then
        exit 1
    fi
    if [[ "$assignment" == net.ipv4.conf.all.rp_filter=* ]]; then
        printf '%s\n' "$value" > "${FAKE_SYSCTL_STATE_DIR}/all"
    else
        printf '%s\n' "$value" > "${FAKE_SYSCTL_STATE_DIR}/iface"
    fi
    exit 0
fi
exit 2
FAKE_SYSCTL
chmod +x "$fake_sysctl"

firewall_log="${TMP_DIR}/firewall.log"
firewall_state_file="${TMP_DIR}/xray-tun.firewall"
fake_nft="${TMP_DIR}/nft"
fake_iptables="${TMP_DIR}/iptables"
fake_ip6tables="${TMP_DIR}/ip6tables"
fake_nft_state="${TMP_DIR}/nft.state"
cat > "$fake_nft" <<'FAKE_NFT'
#!/usr/bin/env bash
printf 'nft %s\n' "$*" >> "${ORDER_LOG:-$FIREWALL_LOG}"
if [[ "${FAKE_NFT_FAIL:-false}" == "true" ]]; then
    exit 1
fi
if [[ "${FAKE_NFT_VERIFY_FAIL:-false}" == "true" && "$*" == *"list"* ]]; then
    exit 1
fi
if [[ "$*" == *"add table inet xray_client_tun"* ]]; then
    : > "$FAKE_NFT_STATE"
fi
if [[ "$*" == *"delete table inet xray_client_tun"* ]]; then
    rm -f "$FAKE_NFT_STATE"
fi
if [[ "$*" == *"list"* ]]; then
    if [[ "${FAKE_NFT_TABLE_EXISTS:-false}" == "true" \
        || -f "$FAKE_NFT_STATE" ]]; then
        echo 'table inet xray_client_tun'
        exit 0
    fi
    exit 1
fi
exit 0
FAKE_NFT
cat > "$fake_iptables" <<'FAKE_IPTABLES'
#!/usr/bin/env bash
printf 'iptables %s\n' "$*" >> "${ORDER_LOG:-$FIREWALL_LOG}"
[[ "${FAKE_IPTABLES_FAIL:-false}" == "true" ]] && exit 1
if [[ "$*" == *" -L "* && "${FAKE_IPTABLES_CHAIN_EXISTS:-false}" == "true" ]]; then
    exit 0
fi
if [[ "$*" == *" -L "* ]]; then
    exit 1
fi
exit 0
FAKE_IPTABLES
cat > "$fake_ip6tables" <<'FAKE_IP6TABLES'
#!/usr/bin/env bash
printf 'ip6tables %s\n' "$*" >> "${ORDER_LOG:-$FIREWALL_LOG}"
[[ "${FAKE_IP6TABLES_FAIL:-false}" == "true" ]] && exit 1
if [[ "$*" == *" -L "* && "${FAKE_IP6TABLES_CHAIN_EXISTS:-false}" == "true" ]]; then
    exit 0
fi
if [[ "$*" == *" -L "* ]]; then
    exit 1
fi
exit 0
FAKE_IP6TABLES
chmod +x "$fake_nft" "$fake_iptables" "$fake_ip6tables"

run_tun_helper() {
    IP_BIN="$fake_ip" IP_LOG="$ip_log" \
        SYSCTL_BIN="$fake_sysctl" SYSCTL_LOG="$sysctl_log" \
        FAKE_SYSCTL_STATE_DIR="$sysctl_state_dir" \
        NFT_BIN="$fake_nft" IPTABLES_BIN="$fake_iptables" \
        IP6TABLES_BIN="$fake_ip6tables" FIREWALL_LOG="$firewall_log" \
        ORDER_LOG="${ORDER_LOG:-}" \
        FAKE_NFT_VERIFY=true \
        FAKE_NFT_STATE="$fake_nft_state" \
        XRAY_TUN_STATE_FILE="$tun_state_file" \
        XRAY_TUN_UID_STATE_FILE="$tun_uid_state_file" \
        XRAY_TUN_FIREWALL_STATE_FILE="$firewall_state_file" \
        XRAY_TUN_BYPASS_UID=4242 \
        "$TUN_ROUTE_HELPER" "$@"
}

run_firewall_helper() {
    env \
        IP_BIN="$fake_ip" IP_LOG="$ip_log" \
        SYSCTL_BIN="$fake_sysctl" SYSCTL_LOG="$sysctl_log" \
        FAKE_SYSCTL_STATE_DIR="$sysctl_state_dir" \
        NFT_BIN="$fake_nft" IPTABLES_BIN="$fake_iptables" \
        IP6TABLES_BIN="$fake_ip6tables" FIREWALL_LOG="$firewall_log" \
        FAKE_NFT_VERIFY="${FAKE_NFT_VERIFY:-true}" \
        FAKE_NFT_STATE="$fake_nft_state" \
        FAKE_NFT_TABLE_EXISTS="${FAKE_NFT_TABLE_EXISTS:-false}" \
        FAKE_NFT_FAIL="${FAKE_NFT_FAIL:-false}" \
        FAKE_NFT_VERIFY_FAIL="${FAKE_NFT_VERIFY_FAIL:-false}" \
        FAKE_IPTABLES_FAIL="${FAKE_IPTABLES_FAIL:-false}" \
        FAKE_IP6TABLES_FAIL="${FAKE_IP6TABLES_FAIL:-false}" \
        XRAY_TUN_STATE_FILE="$tun_state_file" \
        XRAY_TUN_UID_STATE_FILE="$tun_uid_state_file" \
        XRAY_TUN_FIREWALL_STATE_FILE="$firewall_state_file" \
        XRAY_TUN_BYPASS_UID=4242 \
        "$TUN_ROUTE_HELPER" "$@"
}

run_tun_helper up
run_tun_helper up
run_tun_helper status >/dev/null
run_tun_helper down
run_tun_helper down

assert_file_contains "$ip_log" '-4 route replace default dev xray0 table 1001'
assert_file_contains "$ip_log" '-4 rule add priority 9990 uidrange 4242-4242 lookup main'
assert_file_contains "$ip_log" '-4 rule add priority 10000 fwmark 255 lookup main'
assert_file_contains "$ip_log" '-4 rule add priority 10010 uidrange 0-4294967294 lookup 1001'
assert_file_contains "$ip_log" '-6 route replace default dev xray0 table 1001'
assert_file_contains "$ip_log" '-6 rule add priority 10000 fwmark 255 lookup main'
assert_file_contains "$ip_log" '-6 rule add priority 10010 uidrange 0-4294967294 lookup 1001'
assert_file_contains "$ip_log" '-4 route delete default dev xray0 table 1001'
assert_file_contains "$ip_log" '-6 route delete default dev xray0 table 1001'
assert_file_contains "$sysctl_log" '-w net.ipv4.conf.all.rp_filter=0'
assert_file_contains "$sysctl_log" '-w net.ipv4.conf.xray0.rp_filter=0'
assert_file_contains "$sysctl_log" '-w net.ipv4.conf.all.rp_filter=1'

race_count_file="${TMP_DIR}/link-attempts"
IP_BIN="$fake_ip" IP_LOG="$ip_log" \
    SYSCTL_BIN="$fake_sysctl" SYSCTL_LOG="$sysctl_log" \
    FAKE_SYSCTL_STATE_DIR="$sysctl_state_dir" \
    FAKE_IP_LINK_FAILURES=2 FAKE_IP_COUNT_FILE="$race_count_file" \
    XRAY_TUN_WAIT_ATTEMPTS=3 XRAY_TUN_WAIT_INTERVAL=0 \
    NFT_BIN="$fake_nft" IPTABLES_BIN="$fake_iptables" \
    IP6TABLES_BIN="$fake_ip6tables" FIREWALL_LOG="$firewall_log" \
    FAKE_NFT_VERIFY=true FAKE_NFT_STATE="$fake_nft_state" \
    XRAY_TUN_FIREWALL_STATE_FILE="$firewall_state_file" \
    XRAY_TUN_STATE_FILE="$tun_state_file" \
    XRAY_TUN_UID_STATE_FILE="$tun_uid_state_file" \
    XRAY_TUN_BYPASS_UID=4242 \
    "$TUN_ROUTE_HELPER" up
[[ "$(< "$race_count_file")" -eq 3 ]] \
    || fail "TUN helper should wait until xray0 appears"
run_tun_helper down

echo "[4b/9] TUN protects inbound connection replies"
NFT_BIN="$fake_nft" IPTABLES_BIN="$fake_iptables" \
    IP6TABLES_BIN="$fake_ip6tables" FIREWALL_LOG="$firewall_log" \
    FAKE_NFT_VERIFY=true XRAY_TUN_FIREWALL_STATE_FILE="$firewall_state_file" \
    run_tun_helper up
assert_file_contains "$firewall_log" 'table inet xray_client_tun'
assert_file_contains "$firewall_log" 'iifname xray0 return'
assert_file_contains "$firewall_log" 'ct state new'
assert_file_contains "$firewall_log" 'ct mark set 255'
assert_file_contains "$firewall_log" 'meta mark set 255'
assert_file_contains "$firewall_log" 'echo-reply'
run_tun_helper down

echo "[4c/9] TUN firewall backend fallback and fail-closed setup"
firewall_log="${TMP_DIR}/fallback-firewall.log"
FAKE_NFT_FAIL=true run_firewall_helper up
assert_file_contains "$firewall_log" 'iptables -t mangle -N XRAY_TUN_PREROUTING'
assert_file_contains "$firewall_log" 'ip6tables -t mangle -N XRAY_TUN_PREROUTING'
run_firewall_helper down

if FAKE_NFT_TABLE_EXISTS=true run_firewall_helper up >/dev/null 2>&1; then
    fail "TUN setup should reject an existing unmanaged nftables table"
fi
assert_file_not_contains "$firewall_log" 'nft delete table inet xray_client_tun'

order_log="${TMP_DIR}/order.log"
: > "$order_log"
ORDER_LOG="$order_log" run_firewall_helper up
firewall_line=$(grep -n 'nft add table inet xray_client_tun' "$order_log" | cut -d: -f1)
route_line=$(grep -n -- '-4 route replace default dev xray0 table 1001' "$order_log" | cut -d: -f1)
[[ -n "$firewall_line" && -n "$route_line" && "$firewall_line" -lt "$route_line" ]] \
    || fail "firewall protection must be installed before TUN policy routes"
ORDER_LOG="$order_log" run_firewall_helper down
assert_file_contains "$order_log" 'nft delete table inet xray_client_tun'

: > "$ip_log"
if FAKE_NFT_FAIL=true FAKE_IPTABLES_FAIL=true FAKE_IP6TABLES_FAIL=true \
    run_firewall_helper up >/dev/null 2>&1; then
    fail "TUN setup should fail when every firewall backend fails"
fi
assert_file_not_contains "$ip_log" 'route replace default dev xray0 table 1001'

printf '1\n' > "${sysctl_state_dir}/all"
printf '1\n' > "${sysctl_state_dir}/iface"
if FAKE_NFT_VERIFY_FAIL=true run_firewall_helper up >/dev/null 2>&1; then
    fail "TUN setup should fail when firewall verification fails"
fi
[[ "$(< "${sysctl_state_dir}/all")" -eq 1 ]] \
    || fail "firewall verification failure should restore global rp_filter"

conflict_ip_log="${TMP_DIR}/conflict-ip.log"
if IP_BIN="$fake_ip" IP_LOG="$conflict_ip_log" \
    SYSCTL_BIN="$fake_sysctl" SYSCTL_LOG="$sysctl_log" \
    FAKE_SYSCTL_STATE_DIR="$sysctl_state_dir" \
    FAKE_IP_RULE_CONFLICT=true XRAY_TUN_WAIT_INTERVAL=0 \
    NFT_BIN="$fake_nft" IPTABLES_BIN="$fake_iptables" \
    IP6TABLES_BIN="$fake_ip6tables" FIREWALL_LOG="$firewall_log" \
    FAKE_NFT_VERIFY=true FAKE_NFT_STATE="$fake_nft_state" \
    XRAY_TUN_FIREWALL_STATE_FILE="$firewall_state_file" \
    XRAY_TUN_STATE_FILE="$tun_state_file" \
    XRAY_TUN_UID_STATE_FILE="$tun_uid_state_file" \
    XRAY_TUN_BYPASS_UID=4242 \
    "$TUN_ROUTE_HELPER" up >/dev/null 2>&1; then
    fail "TUN helper should reject occupied policy-rule priorities"
fi
assert_file_not_contains "$conflict_ip_log" \
    '-4 route delete default dev xray0 table 1001'

printf '1\n' > "${sysctl_state_dir}/all"
printf '1\n' > "${sysctl_state_dir}/iface"
if IP_BIN="$fake_ip" IP_LOG="$ip_log" \
    SYSCTL_BIN="$fake_sysctl" SYSCTL_LOG="$sysctl_log" \
    FAKE_SYSCTL_STATE_DIR="$sysctl_state_dir" FAKE_SYSCTL_FAIL_IFACE=true \
    NFT_BIN="$fake_nft" IPTABLES_BIN="$fake_iptables" \
    IP6TABLES_BIN="$fake_ip6tables" FIREWALL_LOG="$firewall_log" \
    FAKE_NFT_VERIFY=true FAKE_NFT_STATE="$fake_nft_state" \
    XRAY_TUN_FIREWALL_STATE_FILE="$firewall_state_file" \
    XRAY_TUN_STATE_FILE="$tun_state_file" \
    XRAY_TUN_UID_STATE_FILE="$tun_uid_state_file" \
    XRAY_TUN_BYPASS_UID=4242 XRAY_TUN_WAIT_INTERVAL=0 \
    "$TUN_ROUTE_HELPER" up >/dev/null 2>&1; then
    fail "TUN helper should fail if rp_filter cannot be disabled"
fi
[[ "$(< "${sysctl_state_dir}/all")" -eq 1 ]] \
    || fail "TUN helper should restore global rp_filter after partial setup failure"

echo "[5/9] normal and TUN systemd units"
normal_systemd_dir="${TMP_DIR}/systemd-normal"
tun_systemd_dir="${TMP_DIR}/systemd-tun"
mkdir -p "$normal_systemd_dir" "$tun_systemd_dir"
(
    set --
    export LINUX_SETUP_SOURCE_ONLY=true
    # shellcheck source=linux_setup.sh
    source "$LINUX_SETUP"
    XRAY_SYSTEMD_DIR="$normal_systemd_dir"
    TUN_MODE=false
    write_systemd_service
)
(
    set -- --tun
    export LINUX_SETUP_SOURCE_ONLY=true
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
assert_file_contains "$normal_unit" 'User=nobody'
assert_file_not_contains "$normal_unit" 'DynamicUser=true'
root_systemd_dir="${TMP_DIR}/systemd-root"
mkdir -p "$root_systemd_dir"
(
    set --
    export LINUX_SETUP_SOURCE_ONLY=true
    export XRAY_SERVICE_USER=root
    # shellcheck source=linux_setup.sh
    source "$LINUX_SETUP"
    XRAY_SYSTEMD_DIR="$root_systemd_dir"
    TUN_MODE=false
    write_systemd_service
)
assert_file_contains "${root_systemd_dir}/xray-client.service" 'User=root'
assert_file_contains "$tun_unit" 'Wants=xray-client-tun-routing.service'
assert_file_contains "$tun_unit" 'User=xray-tun'
assert_file_contains "$tun_unit" 'DynamicUser=true'
assert_file_contains "$route_unit" 'After=xray-client.service'
assert_file_contains "$route_unit" 'Requires=xray-client.service'
assert_file_contains "$route_unit" 'BindsTo=xray-client.service'
assert_file_contains "$route_unit" 'ExecStart=/usr/local/libexec/xray-client-tun-route up'
assert_file_contains "$route_unit" 'ExecStop=/usr/local/libexec/xray-client-tun-route down'
assert_file_contains "$route_unit" 'RemainAfterExit=yes'

echo "[6/9] TUN support install and removal lifecycle"
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
    export LINUX_SETUP_SOURCE_ONLY=true
    # shellcheck source=linux_setup.sh
    source "$LINUX_SETUP"
    XRAY_SYSTEMD_DIR="$lifecycle_systemd_dir"
    XRAY_TUN_HELPER_PATH="$lifecycle_helper"
    install_tun_routing
    [[ -x "$lifecycle_helper" ]] || fail "installed TUN helper should be executable"
    [[ -f "${lifecycle_systemd_dir}/xray-client-tun-routing.service" ]] \
        || fail "TUN routing unit should be installed"
    PATH="${fake_bin}:$PATH" IP_BIN="$fake_ip" IP_LOG="$ip_log" \
        SYSCTL_BIN="$fake_sysctl" SYSCTL_LOG="$sysctl_log" \
        FAKE_SYSCTL_STATE_DIR="$sysctl_state_dir" \
        XRAY_TUN_STATE_FILE="$tun_state_file" \
        XRAY_TUN_UID_STATE_FILE="$tun_uid_state_file" \
        XRAY_TUN_BYPASS_UID=4242 \
        SYSTEMCTL_LOG="$systemctl_log" remove_tun_routing
)

[[ ! -e "$lifecycle_helper" ]] || fail "TUN helper should be removed"
[[ ! -e "${lifecycle_systemd_dir}/xray-client-tun-routing.service" ]] \
    || fail "TUN routing unit should be removed"
assert_file_contains "$systemctl_log" 'stop xray-client-tun-routing.service'
assert_file_contains "$systemctl_log" 'disable xray-client-tun-routing.service'

echo "[7/9] install, status, and clean wire the TUN lifecycle"
(
    set --
    export LINUX_SETUP_SOURCE_ONLY=true
    # shellcheck source=linux_setup.sh
    source "$LINUX_SETUP"
    assert_text_contains "$(declare -f do_install)" 'remove_tun_routing'
    assert_text_contains "$(declare -f do_install)" 'install_tun_routing'
    assert_text_contains "$(declare -f do_status)" 'xray-client-tun-routing.service'
    assert_text_contains "$(declare -f do_status)" 'xray-tun-route'
    assert_text_contains "$(declare -f do_clean)" 'remove_tun_routing'
)

echo "[8/9] ensure_geo_data reuses cache/binaries without network"
geo_cache="${TMP_DIR}/geo-cache"
geo_dat="${TMP_DIR}/geo-dat"
geo_fake_bin="${TMP_DIR}/geo-fake-bin"
mkdir -p "${geo_cache}/binaries" "$geo_dat" "$geo_fake_bin"
# Small fixtures; override production min sizes via env for the test.
dd if=/dev/zero of="${geo_cache}/binaries/geoip.dat" bs=1024 count=8 status=none
dd if=/dev/zero of="${geo_cache}/binaries/geosite.dat" bs=1024 count=8 status=none
# Marker must include PRIVATE — truncated real downloads miss this code.
printf 'cached-geoip-PRIVATE' | dd of="${geo_cache}/binaries/geoip.dat" conv=notrunc status=none
printf 'cached-geosite' | dd of="${geo_cache}/binaries/geosite.dat" conv=notrunc status=none
cat > "${geo_fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
touch "${CURL_MARKER}"
echo "curl should not be called when geo cache exists" >&2
exit 99
EOF
chmod +x "${geo_fake_bin}/curl"
(
    set --
    export LINUX_SETUP_SOURCE_ONLY=true
    export DEVTOOLS_CACHE_DIR="$geo_cache"
    export GEOIP_MIN_BYTES=1024
    export GEOSITE_MIN_BYTES=1024
    # shellcheck source=linux_setup.sh
    source "$LINUX_SETUP"
    CACHE_DIR="$geo_cache"
    CURL_MARKER="${TMP_DIR}/geo-curl-called" PATH="${geo_fake_bin}:$PATH" \
        ensure_geo_data "$geo_dat"
)
[[ ! -e "${TMP_DIR}/geo-curl-called" ]] || fail "ensure_geo_data should not call curl when cache exists"
[[ -f "${geo_dat}/geoip.dat" ]] || fail "geoip.dat should be installed from cache"
[[ -f "${geo_dat}/geosite.dat" ]] || fail "geosite.dat should be installed from cache"
grep -q 'cached-geoip-PRIVATE' "${geo_dat}/geoip.dat" || fail "geoip.dat content should come from cache"
grep -q 'cached-geosite' "${geo_dat}/geosite.dat" || fail "geosite.dat content should come from cache"

echo "[9/9] truncated geoip without PRIVATE is replaced from cache"
geo_trunc_dat="${TMP_DIR}/geo-trunc-dat"
mkdir -p "$geo_trunc_dat"
# ~3.9MB-style truncated file: large enough for old 64KiB check, missing PRIVATE
dd if=/dev/zero of="${geo_trunc_dat}/geoip.dat" bs=1024 count=4000 status=none
dd if=/dev/zero of="${geo_trunc_dat}/geosite.dat" bs=1024 count=8 status=none
printf 'truncated-no-marker' | dd of="${geo_trunc_dat}/geoip.dat" conv=notrunc status=none
printf 'old-geosite' | dd of="${geo_trunc_dat}/geosite.dat" conv=notrunc status=none
rm -f "${TMP_DIR}/geo-curl-called"
(
    set --
    export LINUX_SETUP_SOURCE_ONLY=true
    export DEVTOOLS_CACHE_DIR="$geo_cache"
    export GEOIP_MIN_BYTES=1024
    export GEOSITE_MIN_BYTES=1024
    # shellcheck source=linux_setup.sh
    source "$LINUX_SETUP"
    CACHE_DIR="$geo_cache"
    CURL_MARKER="${TMP_DIR}/geo-curl-called" PATH="${geo_fake_bin}:$PATH" \
        ensure_geo_data "$geo_trunc_dat"
)
[[ ! -e "${TMP_DIR}/geo-curl-called" ]] || fail "truncated geoip should be fixed from cache without curl"
grep -q 'cached-geoip-PRIVATE' "${geo_trunc_dat}/geoip.dat" \
    || fail "truncated geoip.dat should be replaced from cache"
grep -q 'PRIVATE' "${geo_trunc_dat}/geoip.dat" \
    || fail "replaced geoip.dat must contain PRIVATE"

echo "PASS: linux_setup TUN regression checks"
