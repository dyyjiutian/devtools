#!/usr/bin/env bash
# Optional smoke test for a built alinux3-devbox image. Not registered in
# default Bazel tests because it needs a Docker daemon and the built image.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALINUX_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE="${DEVTOOLS_TEST_IMAGE:-alinux3-devbox:latest}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ -x "${ALINUX_DIR}/bootstrap.sh" ]] || \
  fail "missing executable bootstrap.sh"
bash -n "${ALINUX_DIR}/bootstrap.sh"

command -v docker >/dev/null 2>&1 || fail "docker command not found"
docker image inspect "$IMAGE" >/dev/null 2>&1 || \
  fail "Docker image is not available: ${IMAGE}"

docker run --rm --platform linux/amd64 --user admin "$IMAGE" bash -c '
  set -euo pipefail
  test "${USER}" = admin
  test "$(pwd)" = /home/admin
  test -d "$HOME/.cache"
  test -w "$HOME/.cache"
  mkdir -p "$HOME/.cache/starship"
'

docker run --rm --platform linux/amd64 --user admin "$IMAGE" bash -lc '
  set -euo pipefail
  test "$(id -un)" = admin
  test "$HOME" = /home/admin
  command -v git
  command -v lazygit
  command -v delta
  command -v vim
  command -v nvim
  command -v tmux
  command -v starship
  command -v fzf
  command -v zoxide
  command -v jq
  command -v tree
  command -v bat
  command -v rg
  command -v docker
  command -v bazel
  command -v yazi
  command -v go
  command -v java
  command -v claude
  command -v codex
  command -v agent || command -v cursor-agent
  test ! -e "$HOME/.claude/.profile-keys"
  test ! -e "$HOME/.codex/.profile-keys"
  test -f "$HOME/.local/share/blesh/ble.sh"
  test -f "$HOME/.bashrc"
  grep -q "Lightweight Bash Plugins (devtools)" "$HOME/.bashrc"
  test -f "$HOME/.blerc"
  test -f "$HOME/.config/starship.toml"
  test -f "$HOME/.vimrc"
  test -f "$HOME/.config/nvim/init.lua"
  test -d "$HOME/.local/share/nvim/lazy/lazy.nvim"
  test -d "$HOME/.local/share/nvim/lazy/tokyonight.nvim"
  test -d "$HOME/.local/share/nvim/lazy/nvim-treesitter"
  test -d "$HOME/.local/share/nvim/lazy/telescope.nvim"
  test -d "$HOME/.local/share/nvim/lazy/nvim-cmp"
  test "$(find "$HOME/.local/share/nvim/lazy" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d " ")" -ge 40
  test -d "$HOME/.local/share/nvim/mason/packages/bash-language-server"
  test -x "$HOME/.local/share/nvim/mason/bin/bash-language-server" \
    -o -L "$HOME/.local/share/nvim/mason/bin/bash-language-server"
  vim --version | head -1 | grep -F 'Vi IMproved 9.'
  test -d "$HOME/.vim/plugged/coc.nvim"
  test -d "$HOME/.config/coc/extensions/node_modules/coc-sh"
  test -f "$HOME/.tmux.conf"
  test -x "$HOME/.local/bin/git-rb"
  ! git config --global --get user.name
  ! git config --global --get user.email
  git config --global --get pull.rebase | grep -qx true
'

if [[ "${DEVTOOLS_TEST_DIND:-}" == "1" ]]; then
  docker run --rm --privileged --platform linux/amd64 "$IMAGE" bash -lc '
    set -euo pipefail
    docker info >/dev/null
    docker version >/dev/null
  '
fi

echo "PASS: ${IMAGE} toolchain and configuration"
