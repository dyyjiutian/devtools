#!/usr/bin/env bash
# Real nvim operations after setup.sh (plugins + config).
set -euo pipefail

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

if ! command -v nvim >/dev/null 2>&1; then
  echo "FAIL: nvim not on PATH after setup" >&2
  exit 1
fi

assert_file_exists "$HOME/.config/nvim/init.lua" "setup deployed nvim config"

real_file="$MODULE_ROOT/setup.sh"
assert_file_exists "$real_file" "opens a real module file"

nvim --headless \
  -c "edit $real_file" \
  -c "if line('\$') < 10 | cquit 2 | endif" \
  -c "qa!"
pass "nvim opens a real file ($DEVTOOLS_TEST_PROFILE)"

work="$(mktemp -d "${TMPDIR:-/tmp}/nvim-e2e.XXXXXX")"
git init -q "$work"
git -C "$work" config user.email "e2e@example.com"
git -C "$work" config user.name "E2E"
printf 'e2e_unique_marker_42\nsecond line\n' >"$work/sample.sh"
git -C "$work" add sample.sh
git -C "$work" commit -qm 'e2e sample'

nvim --headless \
  -c "cd $work" \
  -c "edit sample.sh" \
  -c "if !exists(':Git') | cquit 3 | endif" \
  -c "Git blame" \
  -c "sleep 800m" \
  -c "if bufname('%') !~? 'blame\\|fugitive' && &filetype !=# 'fugitiveblame' | cquit 4 | endif" \
  -c "qa!"
pass "nvim Git blame works ($DEVTOOLS_TEST_PROFILE)"
if ! command -v rg >/dev/null 2>&1; then
  echo "FAIL: ripgrep (rg) not on PATH after setup" >&2
  exit 1
fi
rg_hits="$(rg -n e2e_unique_marker_42 "$work/sample.sh")"
assert_contains "$rg_hits" "e2e_unique_marker_42" "rg finds the workspace marker"

nvim --headless \
  -c "cd $work" \
  -c "edit sample.sh" \
  -c "lua if vim.fn.executable('rg') ~= 1 then vim.cmd('cquit 5') end" \
  -c "lua local ok, builtin = pcall(require, 'telescope.builtin'); if not ok then vim.cmd('cquit 6') end" \
  -c "lua local ok, err = pcall(function() require('telescope.builtin').grep_string({search='e2e_unique_marker_42'}) end); if not ok then vim.api.nvim_err_writeln(tostring(err)); vim.cmd('cquit 7') end" \
  -c "qa!"
pass "nvim telescope grep_string runs ($DEVTOOLS_TEST_PROFILE)"

nvim --headless \
  -c "cd $work" \
  -c "edit sample.sh" \
  -c "lua local ok, err = pcall(require('telescope.builtin').current_buffer_fuzzy_find); if not ok then vim.api.nvim_err_writeln(tostring(err)); vim.cmd('cquit 8') end" \
  -c "qa!"
pass "nvim current-buffer fuzzy find runs ($DEVTOOLS_TEST_PROFILE)"

echo "PASS: nvim E2E ops ($DEVTOOLS_TEST_PROFILE)"
