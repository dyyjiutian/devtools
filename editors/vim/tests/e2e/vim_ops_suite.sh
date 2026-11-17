#!/usr/bin/env bash
# Real vim operations after setup.sh --upgrade.
set -euo pipefail

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

if ! command -v vim >/dev/null 2>&1; then
  echo "FAIL: vim not on PATH after setup" >&2
  exit 1
fi

assert_file_exists "$HOME/.vimrc" "setup deployed ~/.vimrc"

# A crashing coc.nvim can leave vim waiting forever on exit. Bound every call so
# a hang fails in ~2min instead of burning the whole Bazel test timeout.
# macOS has no timeout(1) unless coreutils is installed; fall back to gtimeout.
VIM_TIMEOUT="${VIM_TIMEOUT:-120}"
run_vim() {
  if command -v timeout >/dev/null 2>&1; then
    timeout -k 10 "$VIM_TIMEOUT" vim "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout -k 10 "$VIM_TIMEOUT" vim "$@"
  else
    vim "$@"
  fi
}

real_file="$MODULE_ROOT/setup.sh"
assert_file_exists "$real_file" "opens a real module file"

run_vim -Nu "$HOME/.vimrc" --not-a-term \
  -c "edit $real_file" \
  -c "if line('\$') < 10 | cquit 2 | endif" \
  -c "qa!"
pass "vim opens a real file ($DEVTOOLS_TEST_PROFILE)"

work="$(mktemp -d "${TMPDIR:-/tmp}/vim-e2e.XXXXXX")"
git init -q "$work"
git -C "$work" config user.email "e2e@example.com"
git -C "$work" config user.name "E2E"
printf 'e2e_unique_marker_42\n' >"$work/sample.sh"
git -C "$work" add sample.sh
git -C "$work" commit -qm 'e2e sample'

run_vim -Nu "$HOME/.vimrc" --not-a-term \
  -c "cd $work" \
  -c "edit sample.sh" \
  -c "if getline(1) !~# 'e2e_unique_marker_42' | cquit 2 | endif" \
  -c "if !exists(':Git') | cquit 3 | endif" \
  -c "Git blame" \
  -c "sleep 800m" \
  -c "if bufname('%') !~? 'blame\\|fugitive' && &filetype !=# 'fugitiveblame' | cquit 4 | endif" \
  -c "qa!"
pass "vim Git blame works ($DEVTOOLS_TEST_PROFILE)"

echo "PASS: vim E2E ops ($DEVTOOLS_TEST_PROFILE)"
