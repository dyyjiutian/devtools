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
ENTRYPOINT="${REPO_ROOT}/docker/alinux3/entrypoint.sh"
DOCKERFILE="${REPO_ROOT}/docker/alinux3/Dockerfile"
BAKE="${REPO_ROOT}/docker/alinux3/docker-bake.hcl"
ROOT_README="${REPO_ROOT}/README.md"
AGENTS_MD="${REPO_ROOT}/AGENTS.md"
CLAUDE_MD="${REPO_ROOT}/CLAUDE.md"
DOCKER_CE_REPO="${REPO_ROOT}/os/lib/repos/docker-ce-8.repo"
DOCKER_CE_ALIYUN="${REPO_ROOT}/os/lib/repos/docker-ce-8-aliyun.repo"

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
assert_file "$ENTRYPOINT"
assert_file "$DOCKERFILE"
assert_file "$BAKE"
assert_file "$DOCKER_CE_REPO"
assert_file "$DOCKER_CE_ALIYUN"
assert_file "$AGENTS_MD"
assert_file "$CLAUDE_MD"

run_bake_dry_run_with_fakes() {
  local bake_help="$1"
  local fake_dir dry_out
  fake_dir="$(mktemp -d "${TMPDIR:-/tmp}/devtools-bake-fake.XXXXXX")"
  mkdir -p "${fake_dir}/gitdir"
  cat >"${fake_dir}/docker" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == buildx && "\${2:-}" == bake && "\${3:-}" == --help ]]; then
  cat <<'HELP'
${bake_help}
HELP
  exit 0
fi
echo "unexpected docker invocation: \$*" >&2
exit 1
EOF
  cat >"${fake_dir}/git" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == -C ]]; then
  shift 2
fi
if [[ "\${1:-}" == rev-parse && "\${2:-}" == --git-common-dir ]]; then
  printf '%s\\n' "${fake_dir}/gitdir"
  exit 0
fi
echo "unexpected git invocation: \$*" >&2
exit 1
EOF
  chmod +x "${fake_dir}/docker" "${fake_dir}/git"
  dry_out="$(PATH="${fake_dir}:${PATH}" IMAGE_TAG=20260815-2140 HTTP_PROXY=http://127.0.0.1:8001 "$BAKE_SH" --dry-run)"
  rm -rf "$fake_dir"
  printf '%s' "$dry_out"
}

bash -n "$BOOTSTRAP" || fail "bootstrap.sh failed bash -n"

bash -n "$ENTRYPOINT" || fail "entrypoint.sh failed bash -n"
help_entry="$("$ENTRYPOINT" --help)"
assert_contains "$help_entry" "privileged" "entrypoint --help mentions --privileged"
assert_contains "$help_entry" "dockerd" "entrypoint --help mentions dockerd"

help_out="$("$BOOTSTRAP" --help)"
assert_contains "$help_out" "dry-run" "bootstrap --help mentions dry-run"
assert_contains "$help_out" "lazygit" "bootstrap --help mentions lazygit"
assert_contains "$help_out" "bat" "bootstrap --help mentions bat"
assert_contains "$help_out" "bazel" "bootstrap --help mentions bazel"
assert_contains "$help_out" "yazi" "bootstrap --help mentions yazi"
bootstrap="$(cat "$BOOTSTRAP")"
assert_contains "$bootstrap" "NVIM_SETUP_STRICT" "bootstrap enables strict nvim plugin install"
assert_contains "$bootstrap" "install_bat" "bootstrap installs bat"
assert_contains "$bootstrap" "install_rg" "bootstrap installs rg"
assert_contains "$bootstrap" "install_yazi" "bootstrap prefers cached yazi"
assert_contains "$bootstrap" 'editors/vim/setup.sh" --upgrade' \
  "bootstrap upgrades Vim so coc.nvim / gd / gr work on Alinux 3"
assert_contains "$bootstrap" "tools/bazel/setup.sh" "bootstrap installs Bazel via tools/bazel"
assert_contains "$bootstrap" "terminal/yazi/setup.sh" "bootstrap configures Yazi"
assert_contains "$bootstrap" "languages/go/setup.sh" "bootstrap installs Go"
assert_contains "$bootstrap" "languages/java/setup.sh" "bootstrap installs Java"
java_setup="$(cat "${REPO_ROOT}/languages/java/setup.sh")"
assert_contains "$java_setup" "source_sdkman_init" \
  "java setup sources sdkman-init.sh under set +u so image bootstrap can use set -u"
assert_contains "$java_setup" "run_sdk" \
  "java setup wraps sdk install/list so optional SDKMAN args do not trip set -u"
assert_contains "$bootstrap" "agents/claude/setup.sh" "bootstrap installs Claude Code"
assert_contains "$bootstrap" "agents/codex/setup.sh" "bootstrap installs Codex CLI"
assert_contains "$bootstrap" "agents/cursor-agent/setup.sh" "bootstrap installs Cursor Agent"
assert_contains "$bootstrap" "cookbook/setup.sh" "bootstrap syncs cookbook skills"
assert_contains "$bootstrap" "--copy" "cookbook skills are copied, not only linked"
assert_contains "$bootstrap" "--target all" "cookbook syncs cursor, claude, and codex"
assert_not_contains "$bootstrap" "setup.sh switch" "bootstrap does not run agent channel switch"
assert_not_contains "$bootstrap" "setup.sh configure" "bootstrap does not run agent configure"
assert_contains "$bootstrap" ".profile-keys" "bootstrap removes agent key files after install"
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
assert_contains "$dockerfile" "COPY --chown=admin:admin tools/bazel" "Dockerfile copies tools/bazel"
assert_contains "$dockerfile" "COPY --chown=admin:admin terminal/yazi" "Dockerfile copies terminal/yazi"
assert_contains "$dockerfile" "COPY --chown=admin:admin languages/go" "Dockerfile copies languages/go"
assert_contains "$dockerfile" "COPY --chown=admin:admin languages/java" "Dockerfile copies languages/java"
assert_contains "$dockerfile" "COPY --chown=admin:admin agents/claude" "Dockerfile copies agents/claude"
assert_contains "$dockerfile" "COPY --chown=admin:admin agents/codex" "Dockerfile copies agents/codex"
assert_contains "$dockerfile" "COPY --chown=admin:admin agents/cursor-agent" "Dockerfile copies agents/cursor-agent"
assert_contains "$dockerfile" "COPY --chown=admin:admin agents/cookbook" "Dockerfile copies agents/cookbook"
assert_contains "$dockerfile" "os/lib/repos/docker-ce-8.repo" "image adds official Docker CE el8"
assert_contains "$dockerfile" "os/lib/repos/docker-ce-8-aliyun.repo" "image adds Aliyun Docker CE el8"
assert_contains "$dockerfile" "docker-ce docker-ce-cli containerd.io" "installs Docker CE packages"
assert_contains "$dockerfile" "usermod -aG docker admin" "admin is in the docker group"
assert_contains "$dockerfile" "devtools-entrypoint" "Dockerfile installs the DinD entrypoint"
assert_contains "$dockerfile" 'ENTRYPOINT ["/usr/local/bin/devtools-entrypoint"]' \
  "root entrypoint starts dockerd then drops to admin"
assert_contains "$dockerfile" "USER root" "image starts as root so the entrypoint can launch dockerd"
assert_contains "$dockerfile" "/usr/local/go/bin" \
  "image PATH includes Go so bash -lc can find go without relying on .zshrc"
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
assert_contains "$dockerfile" "NVIM_SETUP_QUIET=1" \
  "bootstrap quiets nvim progress so BuildKit does not hit the 1MiB step log limit"
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
assert_contains "$dockerignore" "!os/lib/repos/docker-ce-8.repo" \
  "dockerignore keeps the official Docker CE el8 repo in build context"
assert_contains "$dockerignore" "!os/lib/repos/docker-ce-8-aliyun.repo" \
  "dockerignore keeps the Aliyun Docker CE el8 repo in build context"
assert_contains "$dockerignore" "!agents/cookbook/**/*.md" \
  "dockerignore keeps cookbook SKILL.md files"
assert_not_contains "$dockerignore" $'\nagents\n' "dockerignore no longer excludes all of agents"
assert_not_contains "$dockerignore" $'\nlanguages\n' "dockerignore no longer excludes all of languages"
assert_not_contains "$dockerignore" "terminal/yazi\n" "dockerignore keeps terminal/yazi"
assert_not_contains "$dockerignore" $'\ntools/bazel\n' "dockerignore keeps tools/bazel"
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
bake_sh_src="$(cat "$BAKE_SH")"
assert_contains "$bake_sh_src" "docker buildx bake --help" \
  "bake.sh probes local bake CLI before passing --allow"
assert_contains "$bake_sh_src" "Docker CE 26" \
  "bake.sh documents the Docker CE 26 compatibility baseline"
assert_contains "$bake_sh_src" 'fs.read=' "bake.sh can grant worktree git-dir read entitlement"
dry_bake_old="$(run_bake_dry_run_with_fakes $'Usage: docker buildx bake\n  --load\n')"
assert_not_contains "$dry_bake_old" "--allow" \
  "bake.sh omits --allow when the local bake CLI is Docker CE 26 / Buildx without entitlements"
assert_contains "$dry_bake_old" "host.docker.internal:8001" \
  "fake Docker CE 26 bake dry-run still rewrites loopback proxy"
dry_bake_new="$(run_bake_dry_run_with_fakes $'Usage: docker buildx bake\n  --allow\n  --load\n')"
assert_contains "$dry_bake_new" "--allow" \
  "bake.sh passes --allow when the local bake CLI advertises it"
assert_contains "$dry_bake_new" "fs.read=" \
  "bake.sh grants worktree git-dir read entitlement only on newer bake CLI"
agents_md="$(cat "$AGENTS_MD")"
claude_md="$(cat "$CLAUDE_MD")"
assert_contains "$agents_md" "Docker CE 26" \
  "root AGENTS.md records the Docker CE 26 compatibility baseline"
assert_contains "$claude_md" "Docker CE 26" \
  "root CLAUDE.md records the Docker CE 26 compatibility baseline"
docker_readme="$(cat "${REPO_ROOT}/docker/alinux3/README.md")"
assert_contains "$docker_readme" "Docker CE 26" \
  "alinux3 README documents Docker CE 26 bake compatibility"
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
  "${REPO_ROOT}/terminal/tmux/tmux.conf" \
  "${REPO_ROOT}/tools/bazel/setup.sh" \
  "${REPO_ROOT}/terminal/yazi/setup.sh" \
  "${REPO_ROOT}/languages/go/setup.sh" \
  "${REPO_ROOT}/languages/java/setup.sh" \
  "${REPO_ROOT}/agents/claude/setup.sh" \
  "${REPO_ROOT}/agents/codex/setup.sh" \
  "${REPO_ROOT}/agents/cursor-agent/setup.sh" \
  "${REPO_ROOT}/agents/cookbook/setup.sh"
do
  assert_file "$path"
done

docker_ce_repo="$(cat "$DOCKER_CE_REPO")"
docker_ce_aliyun="$(cat "$DOCKER_CE_ALIYUN")"
assert_contains "$docker_ce_repo" "/centos/8/" "official Docker CE repo pins centos/8"
assert_contains "$docker_ce_aliyun" "mirrors.aliyun.com/docker-ce/linux/centos/8/" \
  "Aliyun Docker CE repo pins centos/8"
assert_not_contains "$docker_ce_repo" '$releasever' "official Docker CE repo does not use \$releasever"
assert_not_contains "$docker_ce_aliyun" '$releasever' "Aliyun Docker CE repo does not use \$releasever"

entrypoint="$(cat "$ENTRYPOINT")"
assert_contains "$entrypoint" "dockerd" "entrypoint can start dockerd"
assert_contains "$entrypoint" "overlay2" "entrypoint prefers overlay2"
assert_contains "$entrypoint" "vfs" "entrypoint falls back to vfs when overlay2 fails"
assert_contains "$entrypoint" "runuser" "entrypoint drops privileges with runuser"
assert_contains "$entrypoint" "admin" "entrypoint drops to admin"
assert_not_contains "$entrypoint" "2375" "entrypoint does not expose unencrypted TCP 2375"

echo "PASS: alinux3 image contract"
