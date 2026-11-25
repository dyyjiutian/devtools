#!/usr/bin/env bash
# Regression: fallback 状态机、Reality 凭据校验、备用 xray 配置生成（含密钥不外泄）、
# --help 文档。全部 source-only / fixture，无 root / 网络副作用。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FALLBACK="${SCRIPT_DIR}/fallback.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_eq() {
    local actual="$1" expected="$2" msg="$3"
    [[ "$actual" == "$expected" ]] || fail "${msg}: expected '${expected}', got '${actual}'"
}

assert_file_contains() {
    grep -qF -- "$2" "$1" || fail "$1 should contain: $2"
}

FAKE_KEY="FAKE-PRIVATE-KEY-DO-NOT-LEAK-1234567890"
REALITY_FIXTURE="${TMP_DIR}/reality.json"
cat >"$REALITY_FIXTURE" <<EOF
{
  "dest": "www.icloud.com:443",
  "serverNames": ["www.icloud.com", "www.apple.com"],
  "privateKey": "${FAKE_KEY}",
  "shortIds": ["aabbccdd11223344"],
  "clients": [
    {"id": "00000000-0000-0000-0000-000000000000", "flow": "xtls-rprx-vision", "email": "test@vpn"}
  ]
}
EOF

echo "[1/6] source fallback.sh helpers without root/system side effects"
(
    export FALLBACK_SOURCE_ONLY=true
    # shellcheck source=fallback.sh
    source "$FALLBACK"
    for fn in next_state probe_exit validate_reality_json build_fallback_config read_state write_state; do
        declare -F "$fn" >/dev/null || fail "$fn should be defined"
    done
)

echo "[2/6] next_state: threshold switching + counter resets"
(
    export FALLBACK_SOURCE_ONLY=true
    # shellcheck source=fallback.sh
    source "$FALLBACK"
    assert_eq "$(next_state main 0 0 false 3)" "main 1 0 none" "first failure counts"
    assert_eq "$(next_state main 2 0 false 3)" "fallback 3 0 switch_fallback" "3rd failure switches"
    assert_eq "$(next_state main 2 0 true 3)" "main 0 1 none" "success resets fail counter"
    assert_eq "$(next_state fallback 0 2 true 3)" "main 0 3 switch_main" "3rd success switches back"
    assert_eq "$(next_state fallback 0 2 false 3)" "fallback 1 0 none" "failure resets ok counter"
    assert_eq "$(next_state main 0 0 false 1)" "fallback 1 0 switch_fallback" "threshold=1 immediate"
)

echo "[3/6] validate_reality_json accepts fixture, rejects incomplete material"
(
    export FALLBACK_SOURCE_ONLY=true
    # shellcheck source=fallback.sh
    source "$FALLBACK"
    validate_reality_json "$REALITY_FIXTURE" || fail "fixture should validate"
    python3 -c '
import json, sys
d = json.load(open(sys.argv[1])); del d["privateKey"]
json.dump(d, open(sys.argv[2], "w"))
' "$REALITY_FIXTURE" "${TMP_DIR}/no-key.json"
    if validate_reality_json "${TMP_DIR}/no-key.json"; then
        fail "missing privateKey must be rejected"
    fi
    python3 -c '
import json, sys
d = json.load(open(sys.argv[1])); d["clients"] = []
json.dump(d, open(sys.argv[2], "w"))
' "$REALITY_FIXTURE" "${TMP_DIR}/no-clients.json"
    if validate_reality_json "${TMP_DIR}/no-clients.json"; then
        fail "empty clients must be rejected"
    fi
    echo "not json" >"${TMP_DIR}/garbage.json"
    if validate_reality_json "${TMP_DIR}/garbage.json"; then
        fail "garbage must be rejected"
    fi
)

echo "[4/6] build_fallback_config: loopback Reality inbound, CN direct, rest via WARP"
OUT_CFG="${TMP_DIR}/config.json"
gen_stdout="${TMP_DIR}/gen-stdout.txt"
(
    export FALLBACK_SOURCE_ONLY=true
    # shellcheck source=fallback.sh
    source "$FALLBACK"
    build_fallback_config "$REALITY_FIXTURE" "$OUT_CFG" 8443 40000
) >"$gen_stdout" 2>&1
python3 - "$OUT_CFG" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
ib = d["inbounds"][0]
assert ib["listen"] == "127.0.0.1", "fallback inbound must bind loopback only"
assert ib["port"] == 8443
assert ib["protocol"] == "vless"
rs = ib["streamSettings"]["realitySettings"]
assert rs["serverNames"] == ["www.icloud.com", "www.apple.com"]
assert rs["dest"] == "www.icloud.com:443"
assert ib["settings"]["clients"][0]["flow"] == "xtls-rprx-vision"
tags = {o["tag"]: o["protocol"] for o in d["outbounds"]}
assert tags == {"warp": "socks", "direct": "freedom", "block": "blackhole"}, tags
warp = [o for o in d["outbounds"] if o["tag"] == "warp"][0]
assert warp["settings"]["servers"][0]["port"] == 40000
rules = d["routing"]["rules"]
assert rules[-1]["outboundTag"] == "warp", "default route must go through WARP"
cn = [r for r in rules if r.get("domain") == ["geosite:cn"] or r.get("ip") == ["geoip:cn"]]
assert cn and all(r["outboundTag"] == "direct" for r in cn), "CN traffic must stay direct"
assert any(r.get("ip") == ["geoip:private"] and r["outboundTag"] == "block" for r in rules)
PY
mode="$(stat -c '%a' "$OUT_CFG" 2>/dev/null || stat -f '%Lp' "$OUT_CFG")"
assert_eq "$mode" "600" "generated config contains Reality private key, must be 0600"

echo "[5/6] generation output never leaks the private key"
if grep -qF "$FAKE_KEY" "$gen_stdout"; then
    fail "build_fallback_config stdout/stderr must not contain key material"
fi
assert_file_contains "$OUT_CFG" "$FAKE_KEY"  # key lives only in the 600 file

echo "[6/6] --help documents commands, credential safety and rollback"
help_out="$("$FALLBACK" --help)"
for word in install check status switch clean --exit-ssh --sudo-pass-file --threshold route_localnet; do
    echo "$help_out" | grep -q -- "$word" || fail "help should mention: $word"
done
echo "$help_out" | grep -q '不回显' || fail "help should state credentials are never echoed"

echo "PASS: relay/fallback state-machine + config-generation regression checks"
