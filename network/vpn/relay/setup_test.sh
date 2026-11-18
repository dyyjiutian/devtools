#!/usr/bin/env bash
# Regression: relay 内核参数（conntrack/route_localnet）、历史 DNAT 清扫解析、
# hairpin 公网 IP 判定、--help 文档。全部 source-only / 无 root 副作用。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELAY_SETUP="${SCRIPT_DIR}/setup.sh"
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

assert_eq() {
    local actual="$1" expected="$2" msg="$3"
    [[ "$actual" == "$expected" ]] || fail "${msg}: expected '${expected}', got '${actual}'"
}

echo "[1/6] source relay/setup.sh helpers without root/system side effects"
(
    export RELAY_SETUP_SOURCE_ONLY=true
    # shellcheck source=setup.sh
    source "$RELAY_SETUP"
    declare -F is_public_ip >/dev/null || fail "is_public_ip should be defined"
    declare -F legacy_dnat_targets >/dev/null || fail "legacy_dnat_targets should be defined"
    declare -F write_relay_sysctl >/dev/null || fail "write_relay_sysctl should be defined"
    declare -F rps_mask >/dev/null || fail "rps_mask should be defined"
    assert_eq "$(rps_mask 1)" "1" "1-core mask"
    assert_eq "$(rps_mask 2)" "3" "2-core mask"
    assert_eq "$(rps_mask 4)" "f" "4-core mask"
    assert_eq "$(rps_mask 8)" "ff" "8-core mask"
    if rps_mask 0 >/dev/null 2>&1; then fail "rps_mask 0 must be rejected"; fi
    if rps_mask abc >/dev/null 2>&1; then fail "rps_mask non-numeric must be rejected"; fi
)

echo "[2/6] sysctl conf covers forwarding, BBR, conntrack and route_localnet"
(
    export RELAY_SETUP_SOURCE_ONLY=true
    # shellcheck source=setup.sh
    source "$RELAY_SETUP"
    write_relay_sysctl "${TMP_DIR}/99-vpn-relay.conf"
)
conf="${TMP_DIR}/99-vpn-relay.conf"
assert_file_contains "$conf" "net.ipv4.ip_forward = 1"
assert_file_contains "$conf" "net.ipv4.tcp_congestion_control = bbr"
assert_file_contains "$conf" "net.core.default_qdisc = fq"
assert_file_contains "$conf" "net.ipv4.conf.all.route_localnet = 1"
assert_file_contains "$conf" "net.netfilter.nf_conntrack_max = 262144"
assert_file_contains "$conf" "net.netfilter.nf_conntrack_tcp_timeout_established = 3600"
assert_file_contains "$conf" "net.netfilter.nf_conntrack_tcp_be_liberal = 1"
assert_file_contains "$conf" "net.core.netdev_max_backlog = 16384"
assert_file_contains "$conf" "net.core.netdev_budget = 600"
assert_file_contains "$conf" "net.core.netdev_budget_usecs = 4000"
# 重跑幂等：覆盖写入不追加
(
    export RELAY_SETUP_SOURCE_ONLY=true
    # shellcheck source=setup.sh
    source "$RELAY_SETUP"
    write_relay_sysctl "$conf"
)
n="$(grep -c 'net.ipv4.ip_forward = 1' "$conf")"
assert_eq "$n" "1" "sysctl rewrite must not duplicate entries"

echo "[3/6] legacy_dnat_targets parses only the listen port, ignores Docker chain"
fixture="${TMP_DIR}/nat-s.txt"
cat >"$fixture" <<'EOF'
-P PREROUTING ACCEPT
-A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER
-A PREROUTING -p tcp -m tcp --dport 443 -j DNAT --to-destination 198.51.100.23:443
-A PREROUTING -p tcp -m tcp --dport 8443 -j DNAT --to-destination 1.2.3.4:8443
-A PREROUTING -p tcp -m tcp --dport 4433 -j DNAT --to-destination 5.6.7.8:4433
EOF
(
    export RELAY_SETUP_SOURCE_ONLY=true
    # shellcheck source=setup.sh
    source "$RELAY_SETUP"
    assert_eq "$(legacy_dnat_targets 443 <"$fixture")" "198.51.100.23:443" \
        "port 443 sweep target (4433 must not prefix-match)"
    assert_eq "$(legacy_dnat_targets 8443 <"$fixture")" "1.2.3.4:8443" \
        "port 8443 sweep target"
    assert_eq "$(legacy_dnat_targets 9999 <"$fixture" || true)" "" \
        "no DNAT on unused port"
)

echo "[4/6] is_public_ip guards the OUTPUT hairpin rule"
(
    export RELAY_SETUP_SOURCE_ONLY=true
    # shellcheck source=setup.sh
    source "$RELAY_SETUP"
    for ip in 198.51.100.10 198.51.100.21 100.128.1.1; do
        is_public_ip "$ip" || fail "$ip should be public"
    done
    for ip in 172.18.11.149 10.0.0.1 192.168.1.1 127.0.0.1 169.254.1.1 100.64.1.1 172.31.9.9 ""; do
        if is_public_ip "$ip"; then fail "$ip should NOT be public"; fi
    done
)

echo "[5/6] --help documents new default exit, conntrack and fallback entry"
help_out="$("$RELAY_SETUP" --help)"
echo "$help_out" | grep -q '198.51.100.21' || fail "help should show the Tokyo exit example"
echo "$help_out" | grep -q 'fallback.sh' || fail "help should point to fallback.sh"
echo "$help_out" | grep -q 'conntrack' || fail "help should mention conntrack tuning"
echo "$help_out" | grep -q 'hairpin' || fail "help should mention local hairpin path"
grep -q -- '--comment vpn-relay' "$RELAY_SETUP" \
    || fail "managed rules must carry the vpn-relay marker"
grep -q -- 'TCPMSS --set-mss 1380' "$RELAY_SETUP" \
    || fail "relay must clamp forwarded TCP MSS (cross-border PMTUD blackhole)"
grep -q -- '-t mangle -D FORWARD' "$RELAY_SETUP" \
    || fail "sweep must clean marked mangle FORWARD rules"

echo "[6/6] detect_public_ip prefers metadata and never returns private/docker IPs"
fake_bin="${TMP_DIR}/fake-bin"
mkdir -p "$fake_bin"
cat >"${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
# 模拟：metadata 命中 / 全部失败 两种场景（FAKE_CURL_MODE）
for a in "$@"; do
    case "$a" in
        *100.100.100.200*eipv4)
            [[ "${FAKE_CURL_MODE:-metadata}" == "metadata" ]] && { echo "198.51.100.10"; exit 0; }
            exit 22 ;;
        *100.100.100.200*public-ipv4)
            [[ "${FAKE_CURL_MODE:-metadata}" == "metadata" ]] && { echo "198.51.100.10"; exit 0; }
            exit 22 ;;
        *api4.ipify.org*)
            [[ "${FAKE_CURL_MODE:-metadata}" == "private-echo" ]] && { echo "10.1.2.3"; exit 0; }
            exit 28 ;;
        *ifconfig.me*) exit 28 ;;
    esac
done
exit 28
EOF
cat >"${fake_bin}/hostname" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-I" ]]; then
    echo "172.17.0.1 172.18.11.149 198.51.100.10"
fi
EOF
chmod +x "${fake_bin}/curl" "${fake_bin}/hostname"
(
    export RELAY_SETUP_SOURCE_ONLY=true
    export PATH="${fake_bin}:/usr/bin:/bin"
    # shellcheck source=setup.sh
    source "$RELAY_SETUP"
    export FAKE_CURL_MODE=metadata
    assert_eq "$(detect_public_ip)" "198.51.100.10" "metadata path"
    export FAKE_CURL_MODE=private-echo
    assert_eq "$(detect_public_ip)" "198.51.100.10" "private echo rejected, hostname filtered"
    export FAKE_CURL_MODE=down
    assert_eq "$(detect_public_ip)" "198.51.100.10" "all curl down, hostname filtered"
)

echo "PASS: relay/setup kernel + rule-governance + public-IP regression checks"
