#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  if [[ -n "${TEST_SRCDIR:-}" ]]; then
    REPO_ROOT="${TEST_SRCDIR}/${TEST_WORKSPACE:-_main}"
  else
    REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
  fi
fi

BOOTSTRAP="${REPO_ROOT}/docker/alinux3/bootstrap.sh"
DOCKERFILE="${REPO_ROOT}/docker/alinux3/Dockerfile"
BAKE="${REPO_ROOT}/docker/alinux3/docker-bake.hcl"
ROOT_README="${REPO_ROOT}/README.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_contains() {
  local haystack="$1" needle="$2" message="$3"
  [[ "$haystack" == *"$needle"* ]] || fail "$message"
}

assert_not_contains() {
  local haystack="$1" needle="$2" message="$3"
  [[ "$haystack" != *"$needle"* ]] || fail "$message"
}

assert_file "$BOOTSTRAP"
assert_file "$DOCKERFILE"
assert_file "$BAKE"

bash -n "$BOOTSTRAP" || fail "bootstrap.sh failed bash -n"

help_out="$("$BOOTSTRAP" --help)"
assert_contains "$help_out" "dry-run" "bootstrap --help mentions dry-run"
assert_contains "$help_out" "lazygit" "bootstrap --help mentions lazygit"
assert_contains "$help_out" "bat" "bootstrap --help mentions bat"
bootstrap="$(cat "$BOOTSTRAP")"
assert_contains "$bootstrap" "NVIM_SETUP_STRICT" "bootstrap enables strict nvim plugin install"
assert_contains "$bootstrap" "install_bat" "bootstrap installs bat"
assert_contains "$bootstrap" "install_rg" "bootstrap installs rg"
assert_contains "$bootstrap" 'editors/vim/setup.sh" --upgrade' \
  "bootstrap upgrades Vim so coc.nvim / gd / gr work on Alinux 3"
nvim_setup="$(cat "${REPO_ROOT}/editors/nvim/setup.sh")"
assert_contains "$nvim_setup" "_assert_mason_lsps_installed" \
  "nvim setup fails the image build if bashls was not installed"
nvim_lsp="$(cat "${REPO_ROOT}/editors/nvim/lua/plugins/lsp.lua")"
nvim_tools="$(awk '/require\("mason-tool-installer"\)/,/debounce_hours/' <<<"$nvim_lsp")"
assert_contains "$nvim_tools" '"bashls"' \
  "mason-tool-installer waits for bashls during image bootstrap"

dockerfile="$(cat "$DOCKERFILE")"
assert_contains "$dockerfile" "COPY --chown=admin:admin editors/vim" "Dockerfile copies editors/vim"
assert_contains "$dockerfile" "COPY --chown=admin:admin editors/nvim" "Dockerfile copies editors/nvim"
assert_contains "$dockerfile" "COPY --chown=admin:admin tools/git" "Dockerfile copies tools/git"
assert_contains "$dockerfile" "COPY --chown=admin:admin shell/bash" "Dockerfile copies shell/bash"
assert_contains "$dockerfile" "COPY --chown=admin:admin terminal/tmux" "Dockerfile copies terminal/tmux"
assert_contains "$dockerfile" "USER admin" "image defaults to admin"
assert_contains "$dockerfile" "ENV USER=admin" "image exports USER for non-login bash"
assert_contains "$dockerfile" "chown -R admin:admin /home/admin" "home is owned by admin"
assert_contains "$dockerfile" "/home/admin/.cache" "creates writable cache before nvim bootstrap"
assert_contains "$dockerfile" "WORKDIR /home/admin" "image starts in admin home"
assert_not_contains "$dockerfile" "WORKDIR /workspace" "workspace is not the default workdir"
assert_contains "$dockerfile" "jq tree" "installs jq and tree from the centos package set"
assert_contains "$dockerfile" 'CMD ["bash"]' "image defaults to bash"
assert_contains "$dockerfile" "/usr/sbin" "PATH includes /usr/sbin for groupadd"
assert_contains "$dockerfile" "mirrors.aliyun.com" "rewrites Alinux repos to the public mirror"
assert_contains "$dockerfile" "os/lib/repos/epel-8-aliyun.repo" "image adds Aliyun EPEL 8"
assert_contains "$dockerfile" "devtools-epel-8-aliyun.repo" "EPEL 8 is installed as a managed repo file"
assert_contains "$dockerfile" "docker/alinux3/bootstrap.sh" "Dockerfile copies bootstrap from docker/alinux3"
assert_contains "$dockerfile" "ARG HTTP_PROXY" "accepts HTTP_PROXY build arg"
assert_contains "$dockerfile" "NVIM_SETUP_STRICT=1" "bootstrap fails if nvim plugins are missing"
assert_contains "$dockerfile" 'HTTP_PROXY="${HTTP_PROXY:-}"' "forwards HTTP_PROXY through sudo to bootstrap"
assert_not_contains "$dockerfile" "terminal/vim" "no obsolete terminal/vim path"
assert_not_contains "$dockerfile" "vcs/git" "no obsolete vcs/git path"
assert_not_contains "$dockerfile" "AS full" "no full stage"
assert_not_contains "$dockerfile" "AS ssh" "no ssh stage"
assert_not_contains "$dockerfile" "NVIM_VERSION=0.11" "does not pin Neovim 0.11"

bake="$(cat "$BAKE")"
assert_contains "$bake" 'target "devbox"' "bake defines the devbox target"
assert_contains "$bake" "alinux3-devbox" "bake tags alinux3-devbox"
assert_contains "$bake" 'alinux3-devbox:latest' "bake also tags latest"
assert_not_contains "$bake" "alinux3-mini" "bake target was renamed from alinux3-mini"
assert_not_contains "$bake" "alinux3-minimal" "bake target was renamed from alinux3-minimal"
assert_contains "$bake" 'dockerfile = "docker/alinux3/Dockerfile"' \
  "bake dockerfile path follows the docker/ rename"
assert_contains "$bake" 'platforms  = ["linux/amd64"]' "bake locks linux/amd64"
assert_contains "$bake" "HTTP_PROXY" "bake forwards HTTP_PROXY"
assert_not_contains "$bake" "containers/alinux3" "bake no longer points at containers/"

DOCKERIGNORE="${REPO_ROOT}/.dockerignore"
assert_file "$DOCKERIGNORE"
dockerignore="$(cat "$DOCKERIGNORE")"
assert_contains "$dockerignore" "docker/alinux3/tests" "dockerignore excludes docker tests"
assert_contains "$dockerignore" "!os/lib/repos/epel-8-aliyun.repo" \
  "dockerignore keeps the Aliyun EPEL 8 repo in build context"
assert_not_contains "$dockerignore" "containers/alinux3" \
  "dockerignore no longer refers to containers/"

BAKE_SH="${REPO_ROOT}/docker/alinux3/bake.sh"
assert_file "$BAKE_SH"
bash -n "$BAKE_SH" || fail "bake.sh failed bash -n"
help_bake="$("$BAKE_SH" --help)"
assert_contains "$help_bake" "host.docker.internal" "bake.sh help mentions Docker host proxy"
dry_bake="$(IMAGE_TAG=20260815-2140 HTTP_PROXY=http://127.0.0.1:8001 "$BAKE_SH" --dry-run)"
assert_contains "$dry_bake" "devbox" "bake.sh builds the devbox target"
assert_contains "$dry_bake" "docker/alinux3/docker-bake.hcl" "bake.sh uses the renamed bake file"
assert_not_contains "$dry_bake" "containers/alinux3" "bake.sh dry-run does not use containers/"
assert_contains "$dry_bake" "devbox.context=" "bake.sh sets an explicit build context"
assert_contains "$dry_bake" "TAG=20260815-2140" "bake.sh uses the minute-precision IMAGE_TAG"
assert_contains "$dry_bake" "host.docker.internal:8001" "bake.sh rewrites loopback proxy"
assert_not_contains "$dry_bake" "127.0.0.1:8001" "bake.sh does not pass host loopback proxy"
assert_contains "$(cat "$BAKE_SH")" 'fs.read=' "bake.sh can grant worktree git-dir read entitlement"
assert_not_contains "$bake" "alinux3-full" "bake no longer defines full"
assert_not_contains "$bake" "alinux3-ssh" "bake no longer defines ssh"

[[ ! -e "${REPO_ROOT}/.devcontainer/devcontainer.json" ]] || \
  fail "Dev Container metadata should have been removed"

root_readme="$(cat "$ROOT_README")"
assert_not_contains "$root_readme" "devcontainer" "root README should not advertise Dev Container"
assert_not_contains "$root_readme" "devtools-container-run" "root README should not advertise the old wrapper"

for path in \
  "${REPO_ROOT}/editors/vim/vimrc" \
  "${REPO_ROOT}/editors/nvim/init.lua" \
  "${REPO_ROOT}/tools/git/setup.sh" \
  "${REPO_ROOT}/shell/bash/setup.sh" \
  "${REPO_ROOT}/shell/starship/starship-tokyo-linux.toml" \
  "${REPO_ROOT}/terminal/tmux/tmux.conf"
do
  assert_file "$path"
done

echo "PASS: alinux3 image contract"
