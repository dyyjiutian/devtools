#!/usr/bin/env bash
# Parse commit / PR text and print GitHub Actions outputs for L1/L2/L3.
# If the text contains L1, L2, or L3 as whole tokens, only those layers run.
# If none are present, all three layers run.
set -euo pipefail

msg="${SELECT_LAYERS_MESSAGE:-}"
if [[ $# -gt 0 ]]; then
  msg="$*"
fi
if [[ -z "$msg" && ! -t 0 ]]; then
  msg="$(cat)"
fi

contains_token() {
  local token="$1"
  printf '%s' "$msg" | grep -Eiq "(^|[^A-Za-z0-9])${token}([^A-Za-z0-9]|$)"
}

l1=false
l2=false
l3=false
if contains_token L1; then
  l1=true
fi
if contains_token L2; then
  l2=true
fi
if contains_token L3; then
  l3=true
fi

if [[ "$l1" == false && "$l2" == false && "$l3" == false ]]; then
  l1=true
  l2=true
  l3=true
fi

printf 'l1=%s\nl2=%s\nl3=%s\n' "$l1" "$l2" "$l3"
