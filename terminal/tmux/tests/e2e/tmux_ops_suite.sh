#!/usr/bin/env bash
# Real tmux operations after setup.sh --upgrade.
set -euo pipefail

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
export TMUX_TMPDIR="$HOME"

if ! command -v tmux >/dev/null 2>&1; then
  echo "FAIL: tmux not on PATH after setup" >&2
  exit 1
fi

assert_file_exists "$HOME/.tmux.conf" "setup deployed ~/.tmux.conf"

tmux -L e2e -f "$HOME/.tmux.conf" new-session -d -s ops
trap 'tmux -L e2e kill-server >/dev/null 2>&1 || true' EXIT

prefix="$(tmux -L e2e show -gv prefix)"
assert_eq "$prefix" "C-Space" "prefix is Ctrl-Space"

mouse="$(tmux -L e2e show -gv mouse)"
assert_eq "$mouse" "on" "mouse is enabled"

keys="$(tmux -L e2e list-keys -T copy-mode-vi)"
assert_contains "$keys" "begin-selection" "copy-mode-vi v begins selection"
assert_contains "$keys" "copy-selection" "copy-mode-vi y copies selection"

tmux -L e2e new-window -t ops
tmux -L e2e split-window -h -t ops
tmux -L e2e split-window -v -t ops

windows="$(tmux -L e2e list-windows -t ops | wc -l | tr -d ' ')"
panes="$(tmux -L e2e list-panes -t ops -a | wc -l | tr -d ' ')"
if [[ "$windows" -lt 2 ]]; then
  echo "FAIL: expected at least 2 windows, got $windows" >&2
  exit 1
fi
if [[ "$panes" -lt 3 ]]; then
  echo "FAIL: expected at least 3 panes, got $panes" >&2
  exit 1
fi

pass "tmux ops: prefix, mouse, windows/panes ($DEVTOOLS_TEST_PROFILE)"
echo "PASS: tmux E2E ops ($DEVTOOLS_TEST_PROFILE)"
