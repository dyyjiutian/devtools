#!/usr/bin/env bash
# Regression: manage.sh must persist traffic across Xray reloads (add/remove/sync).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANAGE_SH="${SCRIPT_DIR}/manage.sh"
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

# Live session counters (bytes) read by fake xray; reset to simulate process restart.
SESSION_UP_ALICE=0
SESSION_DOWN_ALICE=0
SESSION_UP_BOB=0
SESSION_DOWN_BOB=0
RESTART_COUNT=0

write_fakes() {
    local fake_bin="$1"
    mkdir -p "$fake_bin"

    cat >"${fake_bin}/xray" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Expected: api stats --server=... -name user>>>NAME@vpn>>>traffic>>>uplink|downlink [--reset]
#        or: api statsquery --server=... -pattern ...
cmd="${1:-}"
sub="${2:-}"
if [[ "$cmd" == "api" && "$sub" == "statsquery" ]]; then
    exit 0
fi
if [[ "$cmd" == "api" && "$sub" == "stats" ]]; then
    name=""
    reset=false
    shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -name) name="$2"; shift 2 ;;
            --reset) reset=true; shift ;;
            --server=*) shift ;;
            --server) shift 2 ;;
            *) shift ;;
        esac
    done
    # name like: user>>>alice@vpn>>>traffic>>>uplink
    # (Avoid `case` with `>>` — bash parses it as redirection.)
    rest="${name#user>>>}"
    if [[ "$rest" == "$name" ]]; then
        echo '{"stat":{"name":"","value":"0"}}'
        exit 0
    fi
    user="${rest%%@*}"
    dir="${name##*>>>}"
    u=$(printf '%s' "$user" | tr '[:lower:]' '[:upper:]')
    case "$dir" in
        uplink) d=UP ;;
        downlink) d=DOWN ;;
        *)
            echo '{"stat":{"name":"","value":"0"}}'
            exit 0
            ;;
    esac
    var="SESSION_${d}_${u}"
    # shellcheck source=/dev/null
    source "${SESSION_STATE}"
    if $reset; then
        printf -v "$var" '%s' "0"
        {
            echo "SESSION_UP_ALICE=${SESSION_UP_ALICE:-0}"
            echo "SESSION_DOWN_ALICE=${SESSION_DOWN_ALICE:-0}"
            echo "SESSION_UP_BOB=${SESSION_UP_BOB:-0}"
            echo "SESSION_DOWN_BOB=${SESSION_DOWN_BOB:-0}"
        } >"${SESSION_STATE}"
        echo '{"stat":{"name":"'"$name"'","value":"0"}}'
        exit 0
    fi
    val="${!var-}"
    val="${val:-0}"
    echo "{\"stat\":{\"name\":\"${name}\",\"value\":\"${val}\"}}"
    exit 0
fi
echo "unexpected xray invocation: $*" >&2
exit 1
EOF
    chmod +x "${fake_bin}/xray"

    cat >"${fake_bin}/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "systemctl $*" >>"${SYSTEMCTL_LOG}"
case "${1:-}" in
    restart)
        # Simulate Xray process restart: live counters drop to zero.
        cat >"${SESSION_STATE}" <<STATE
SESSION_UP_ALICE=0
SESSION_DOWN_ALICE=0
SESSION_UP_BOB=0
SESSION_DOWN_BOB=0
STATE
        echo $(( ${RESTART_COUNT:-0} + 1 )) >"${RESTART_COUNT_FILE}"
        ;;
    is-active) exit 0 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "${fake_bin}/systemctl"
}

setup_env() {
    FAKE_BIN="${TMP_DIR}/fake-bin"
    SESSION_STATE="${TMP_DIR}/session.env"
    SYSTEMCTL_LOG="${TMP_DIR}/systemctl.log"
    RESTART_COUNT_FILE="${TMP_DIR}/restart.count"
    TRAFFIC_STORE="${TMP_DIR}/traffic.tsv"
    CONFIG_CACHE="${TMP_DIR}/vpn_exit_config"
    XRAY_CONFIG="${TMP_DIR}/xray-config.json"
    rm -f "$TRAFFIC_STORE"
    : >"$SYSTEMCTL_LOG"
    echo 0 >"$RESTART_COUNT_FILE"
    cat >"$SESSION_STATE" <<'EOF'
SESSION_UP_ALICE=0
SESSION_DOWN_ALICE=0
SESSION_UP_BOB=0
SESSION_DOWN_BOB=0
EOF
    write_fakes "$FAKE_BIN"

    cat >"$CONFIG_CACHE" <<'EOF'
PRIVATE_KEY="test-priv"
PUBLIC_KEY="test-pub"
SHORT_ID="abcd1234"
LISTEN_PORT=443
REALITY_SNI="www.icloud.com"
USERS="alice bob"
USER_alice_UUID="11111111-1111-1111-1111-111111111111"
USER_alice_QUOTA_GB=0
USER_bob_UUID="22222222-2222-2222-2222-222222222222"
USER_bob_QUOTA_GB=10
EOF

    cat >"$XRAY_CONFIG" <<'EOF'
{
  "inbounds": [
    {
      "protocol": "vless",
      "settings": {
        "clients": []
      }
    }
  ],
  "routing": {
    "rules": []
  }
}
EOF

    export PATH="${FAKE_BIN}:${PATH}"
    export SESSION_STATE SYSTEMCTL_LOG RESTART_COUNT_FILE
    export MANAGE_SOURCE_ONLY=true
    export VPN_EXIT_CONFIG="$CONFIG_CACHE"
    export VPN_XRAY_BIN="${FAKE_BIN}/xray"
    export VPN_XRAY_CONFIG="$XRAY_CONFIG"
    export VPN_STATS_SERVER="127.0.0.1:10085"
    export VPN_TRAFFIC_STORE="$TRAFFIC_STORE"
    export VPN_SYSTEMCTL="${FAKE_BIN}/systemctl"
}

load_manage() {
    # shellcheck source=manage.sh
    source "$MANAGE_SH"
}

set_session() {
    local user="$1" up="$2" down="$3"
    local u
    u=$(echo "$user" | tr '[:lower:]' '[:upper:]')
    cat >>"$SESSION_STATE" <<EOF
SESSION_UP_${u}=${up}
SESSION_DOWN_${u}=${down}
EOF
    # Keep file as last-write-wins assignments; rewrite cleanly
    local alice_up alice_down bob_up bob_down
    # shellcheck source=/dev/null
    source "$SESSION_STATE"
    alice_up="${SESSION_UP_ALICE:-0}"
    alice_down="${SESSION_DOWN_ALICE:-0}"
    bob_up="${SESSION_UP_BOB:-0}"
    bob_down="${SESSION_DOWN_BOB:-0}"
    case "$user" in
        alice) alice_up=$up; alice_down=$down ;;
        bob) bob_up=$up; bob_down=$down ;;
    esac
    cat >"$SESSION_STATE" <<EOF
SESSION_UP_ALICE=${alice_up}
SESSION_DOWN_ALICE=${alice_down}
SESSION_UP_BOB=${bob_up}
SESSION_DOWN_BOB=${bob_down}
EOF
}

echo "[1/4] get_user_traffic sums persisted store + live session"
setup_env
(
    load_manage
    set_session alice 1000 2000
    traffic_store_set alice 3000 4000
    read -r up down < <(get_user_traffic alice)
    assert_eq "$up" "4000" "alice uplink store+session"
    assert_eq "$down" "6000" "alice downlink store+session"
)

echo "[2/4] reload_xray_clients commits live traffic before restart"
setup_env
(
    load_manage
    load_config
    set_session alice 5000 7000
    set_session bob 100 200
    reload_xray_clients
    # After restart, live session is 0; totals must remain via store
    read -r up down < <(get_user_traffic alice)
    assert_eq "$up" "5000" "alice uplink survives reload"
    assert_eq "$down" "7000" "alice downlink survives reload"
    read -r up down < <(get_user_traffic bob)
    assert_eq "$up" "100" "bob uplink survives reload"
    assert_eq "$down" "200" "bob downlink survives reload"
    # Second reload with new session traffic must accumulate, not replace
    set_session alice 50 60
    reload_xray_clients
    read -r up down < <(get_user_traffic alice)
    assert_eq "$up" "5050" "alice uplink accumulates across reloads"
    assert_eq "$down" "7060" "alice downlink accumulates across reloads"
)

echo "[3/4] reset-stats clears persisted + session counters"
setup_env
(
    load_manage
    load_config
    set_session alice 900 800
    traffic_store_set alice 100 200
    cmd_reset_stats alice
    read -r up down < <(get_user_traffic alice)
    assert_eq "$up" "0" "alice uplink after reset-stats"
    assert_eq "$down" "0" "alice downlink after reset-stats"

    set_session alice 11 22
    set_session bob 33 44
    traffic_store_set alice 1000 2000
    traffic_store_set bob 3000 4000
    cmd_reset_stats all
    read -r up down < <(get_user_traffic alice)
    assert_eq "$up" "0" "alice uplink after reset-stats all"
    assert_eq "$down" "0" "alice downlink after reset-stats all"
    read -r up down < <(get_user_traffic bob)
    assert_eq "$up" "0" "bob uplink after reset-stats all"
    assert_eq "$down" "0" "bob downlink after reset-stats all"
)

echo "[4/4] cmd_add reload preserves existing users' billed traffic"
setup_env
(
    load_manage
    load_config
    set_session alice 10000 20000
    set_session bob 3000 4000
    # Simulate add carol: extend USERS like cmd_add, then reload
    USER_carol_UUID="33333333-3333-3333-3333-333333333333"
    USER_carol_QUOTA_GB=0
    USERS="${USERS} carol"
    write_config
    reload_xray_clients
    read -r up down < <(get_user_traffic alice)
    assert_eq "$up" "10000" "alice uplink preserved after add"
    assert_eq "$down" "20000" "alice downlink preserved after add"
    read -r up down < <(get_user_traffic bob)
    assert_eq "$up" "3000" "bob uplink preserved after add"
    assert_eq "$down" "4000" "bob downlink preserved after add"
    read -r up down < <(get_user_traffic carol)
    assert_eq "$up" "0" "new user starts at zero uplink"
    assert_eq "$down" "0" "new user starts at zero downlink"
)

echo "OK: manage traffic persistence tests passed"
