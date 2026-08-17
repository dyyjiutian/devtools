#!/usr/bin/env bash
# Parse [test#...] tags from commit / PR text and print GitHub Actions outputs.
#
#   [test#L1]          only L1
#   [test#L1,L2]       L1 and L2
#   [test#ut,e2e]      aliases: ut=L1, it=L2, e2e=L3
#   [test#skip]        skip all layers
#
# No [test#...] tag: run L1, L2, and L3.
# Multiple tags are unioned. skip in any tag wins.
# Unknown or empty selectors skip all layers.
set -euo pipefail

msg="${SELECT_LAYERS_MESSAGE:-}"
if [[ $# -gt 0 ]]; then
  msg="$*"
fi
if [[ -z "$msg" && ! -t 0 ]]; then
  msg="$(cat)"
fi

lower="$(printf '%s' "$msg" | tr '[:upper:]' '[:lower:]')"

found=false
skip=false
l1=false
l2=false
l3=false

apply_inner() {
  local inner="$1" tok
  inner="$(printf '%s' "$inner" | tr ',' ' ')"
  set -f
  for tok in $inner; do
    case "$tok" in
      skip) skip=true ;;
      l1|ut) l1=true ;;
      l2|it) l2=true ;;
      l3|e2e) l3=true ;;
    esac
  done
  set +f
}

rest="$lower"
while [[ "$rest" == *'[test#'* ]]; do
  after="${rest#*'[test#'}"
  if [[ "$after" != *']'* ]]; then
    break
  fi
  found=true
  apply_inner "${after%%']'*}"
  rest="${after#*']'}"
done

if [[ "$found" == false ]]; then
  l1=true
  l2=true
  l3=true
elif [[ "$skip" == true || ( "$l1" == false && "$l2" == false && "$l3" == false ) ]]; then
  l1=false
  l2=false
  l3=false
fi

printf 'l1=%s\nl2=%s\nl3=%s\nut=%s\nit=%s\ne2e=%s\n' \
  "$l1" "$l2" "$l3" "$l1" "$l2" "$l3"
