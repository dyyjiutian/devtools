#!/usr/bin/env bash
set -euo pipefail

ip1="$1"
ip2="$2"
fssh=/tmp/fssh.sh
config="$HOME/.ssh/config"
alias1="fssh-${ip1}"
alias2="fssh-${ip2}-2222"
alias3="fssh-${ip1}-2222"
export TMPDIR="$HOME"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_count() {
    local count
    count=$(grep -Fxc "$1" "$2" || true)
    [[ "$count" == "$3" ]] || fail "expected $3 occurrences of $1, got $count"
}
connect() {
    local output
    output=$(printf 'echo FSSH_CONNECTED; exit\n' | bash "$fssh" "$1" -n)
    [[ "$output" == *FSSH_CONNECTED* ]] || fail "fssh login to $1 failed"
}

echo "==> first add: password authentication, key install, and login"
sshpass -e bash "$fssh" -a "fssh@${ip1}"
[[ -f "$config" && -f "$HOME/.ssh/id_ed25519" ]] || fail "missing config or key"
assert_count "Host ${alias1}" "$config" 1
connect "$alias1"
first_key=$(cat "$HOME/.ssh/id_ed25519.pub")
remote_count=$(ssh -F "$config" -o BatchMode=yes "$alias1" \
    'wc -l < ~/.ssh/authorized_keys')
[[ "$remote_count" -eq 1 ]] || fail "expected one remote authorized key"
remote_key=$(ssh -F "$config" -o BatchMode=yes "$alias1" \
    'cat ~/.ssh/authorized_keys')
[[ "$remote_key" == "$first_key" ]] || fail "wrong key on first server"

echo "==> repeated add: reject duplicate without changing config or remote keys"
cp "$config" "$HOME/config-before"
if sshpass -e bash "$fssh" -a "fssh@${ip1}"; then
    fail "duplicate add unexpectedly succeeded"
fi
cmp "$HOME/config-before" "$config"
remote_count=$(ssh -F "$config" -o BatchMode=yes "$alias1" \
    'wc -l < ~/.ssh/authorized_keys')
[[ "$remote_count" -eq 1 ]] || fail "duplicate add changed remote keys"
connect "$alias1"

echo "==> add second server at non-default port"
sshpass -e bash "$fssh" --add "fssh@${ip2}:2222"
assert_count "Host ${alias1}" "$config" 1
assert_count "Host ${alias2}" "$config" 1
[[ "$(cat "$HOME/.ssh/id_ed25519.pub")" == "$first_key" ]] || fail "key was replaced"
connect "$alias1"
connect "$alias2"
remote_count=$(ssh -F "$config" -o BatchMode=yes "$alias2" \
    'wc -l < ~/.ssh/authorized_keys')
[[ "$remote_count" -eq 1 ]] || fail "second server missing key"
remote_key=$(ssh -F "$config" -o BatchMode=yes "$alias2" \
    'cat ~/.ssh/authorized_keys')
[[ "$remote_key" == "$first_key" ]] || fail "wrong key on second server"
cp "$config" "$HOME/config-before"
if sshpass -e bash "$fssh" --add "fssh@${ip2}:2222"; then
    fail "second server duplicate unexpectedly succeeded"
fi
cmp "$HOME/config-before" "$config"

echo "==> add same server on another port with key already authorized"
sshpass -e bash "$fssh" -a "fssh@${ip1}:2222"
assert_count "Host ${alias1}" "$config" 1
assert_count "Host ${alias2}" "$config" 1
assert_count "Host ${alias3}" "$config" 1
remote_count=$(ssh -F "$config" -o BatchMode=yes "$alias3" \
    'wc -l < ~/.ssh/authorized_keys')
[[ "$remote_count" -eq 1 ]] || fail "existing key duplicated"
connect "$alias3"

echo "==> failed authentication leaves existing configuration intact"
cp "$config" "$HOME/config-before"
if SSHPASS=wrong sshpass -e bash "$fssh" -a "fsshother@${ip2}:2222"; then
    fail "invalid credentials unexpectedly succeeded"
fi
cmp "$HOME/config-before" "$config"
connect "$alias1"
connect "$alias2"
echo "PASS: real SSH container scenarios"
