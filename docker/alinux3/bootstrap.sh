#!/usr/bin/env bash
# Non-interactive Alinux 3 image bootstrap. Run as the target user during build.
# Reuses host module setup.sh scripts; does not write git user.name / user.email.

set -euo pipefail

ROOT="${DEVTOOLS_ROOT:-/opt/devtools}"
CACHE_DIR="${DEVTOOLS_CACHE_DIR:-${ROOT}/cache}"
LAZYGIT_VERSION="${LAZYGIT_VERSION:-0.44.1}"
BAT_VERSION="${BAT_VERSION:-0.25.0}"
RG_VERSION="${RG_VERSION:-14.1.1}"
YAZI_VERSION="${YAZI_VERSION:-0.3.3}"
DELTA_VERSION="${DELTA_VERSION:-0.19.2}"
DELTA_TARGET="x86_64-unknown-linux-musl"
DELTA_ARCHIVE="delta-${DELTA_VERSION}-${DELTA_TARGET}.tar.gz"
DELTA_ARCHIVE_SHA256="${DELTA_ARCHIVE_SHA256:-f1ea01ca7728ce3462debc359f39dfc7cbbc1a63224b71fefabf92042864aa1b}"

info()    { echo -e "\033[34m[INFO]\033[0m $1"; }
success() { echo -e "\033[32m[OK]\033[0m $1"; }
warn()    { echo -e "\033[33m[WARN]\033[0m $1"; }
error()   { echo -e "\033[31m[ERROR]\033[0m $1"; }
step()    { echo -e "\033[36m[STEP]\033[0m $1"; }

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [OPTION]

Install and configure the Alinux 3 devbox toolchain for the current user:
  lazygit, git-delta, bat, rg, yazi, bash (ble/fzf/zoxide/starship), git setup,
  vim, nvim, tmux, bazel, go, java, and agent CLIs (no API keys).

Options:
  -h, --help     Show this help
  -n, --dry-run  Preview module setup commands without installing
EOF
}

DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)    usage; exit 0 ;;
    -n|--dry-run) DRY_RUN=true; shift ;;
    *)
      error "unknown option: $1"
      usage >&2
      exit 1
      ;;
  esac
done

run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

require_module() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    error "missing module script: ${path}"
    exit 1
  fi
}

linux_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x86_64" ;;
    *)
      error "this image bootstrap only supports x86_64, got: $(uname -m)"
      exit 1
      ;;
  esac
}

fetch_archive() {
  local cache_rel="$1" url="$2" dest="$3"
  local cached="${CACHE_DIR}/${cache_rel}"
  if [[ -f "$cached" ]]; then
    info "using cache: ${cache_rel}"
    cp "$cached" "$dest"
    return 0
  fi
  curl -fsSL "$url" -o "$dest"
}

install_user_bin() {
  local name="$1" url="$2" cache_rel="$3" member="$4"
  local dest="${HOME}/.local/bin/${name}"
  if command -v "$name" >/dev/null 2>&1; then
    success "${name} already installed: $($name --version 2>/dev/null | head -1 || echo present)"
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[dry-run] install ${name} from ${url}"
    return 0
  fi

  step "install ${name} ..."
  mkdir -p "${HOME}/.local/bin"
  local tmpdir archive
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/devtools-${name}.XXXXXX")"
  archive="${tmpdir}/$(basename "$cache_rel")"
  fetch_archive "$cache_rel" "$url" "$archive"
  tar -xzf "$archive" -C "$tmpdir" "$member"
  install -m 0755 "${tmpdir}/${member}" "$dest"
  rm -rf "$tmpdir"
  success "${name} installed -> ${dest}"
}

install_delta() {
  local url="https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/${DELTA_ARCHIVE}"
  local cache_rel="binaries/${DELTA_ARCHIVE}"
  if command -v delta >/dev/null 2>&1; then
    success "git-delta already installed: $(delta --version | head -1)"
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[dry-run] install git-delta ${DELTA_VERSION}"
    return 0
  fi

  step "install git-delta ${DELTA_VERSION} ..."
  mkdir -p "${HOME}/.local/bin"
  local tmpdir archive actual
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/devtools-delta.XXXXXX")"
  archive="${tmpdir}/${DELTA_ARCHIVE}"
  fetch_archive "$cache_rel" "$url" "$archive"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$archive" | awk '{print $1}')"
    if [[ "$actual" != "$DELTA_ARCHIVE_SHA256" ]]; then
      error "git-delta checksum mismatch: ${actual}"
      rm -rf "$tmpdir"
      exit 1
    fi
  fi
  tar -xzf "$archive" -C "$tmpdir" "delta-${DELTA_VERSION}-${DELTA_TARGET}/delta"
  install -m 0755 "${tmpdir}/delta-${DELTA_VERSION}-${DELTA_TARGET}/delta" "${HOME}/.local/bin/delta"
  rm -rf "$tmpdir"
  success "git-delta installed -> ${HOME}/.local/bin/delta"
}

install_lazygit() {
  local arch lg_arch filename url
  arch="$(linux_arch)"
  lg_arch="$arch"
  filename="lazygit_${LAZYGIT_VERSION}_Linux_${lg_arch}.tar.gz"
  url="https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/${filename}"
  install_user_bin lazygit "$url" "binaries/${filename}" lazygit
}

install_bat() {
  local arch target filename url
  arch="$(linux_arch)"
  target="${arch}-unknown-linux-musl"
  filename="bat-v${BAT_VERSION}-${target}.tar.gz"
  url="https://github.com/sharkdp/bat/releases/download/v${BAT_VERSION}/${filename}"
  install_user_bin bat "$url" "binaries/${filename}" "bat-v${BAT_VERSION}-${target}/bat"
}

install_rg() {
  local arch target filename url
  arch="$(linux_arch)"
  target="${arch}-unknown-linux-musl"
  filename="ripgrep-${RG_VERSION}-${target}.tar.gz"
  url="https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/${filename}"
  install_user_bin rg "$url" "binaries/${filename}" "ripgrep-${RG_VERSION}-${target}/rg"
}

install_yazi() {
  local arch target filename url dest tmpdir archive cached
  arch="$(linux_arch)"
  target="${arch}-unknown-linux-musl"
  filename="yazi-${target}.zip"
  url="https://github.com/sxyazi/yazi/releases/download/v${YAZI_VERSION}/${filename}"
  dest="${HOME}/.local/bin/yazi"
  if command -v yazi >/dev/null 2>&1; then
    success "yazi already installed: $(yazi --version 2>/dev/null | head -1 || echo present)"
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[dry-run] install yazi ${YAZI_VERSION} from ${url}"
    return 0
  fi

  step "install yazi ${YAZI_VERSION} ..."
  mkdir -p "${HOME}/.local/bin"
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/devtools-yazi.XXXXXX")"
  archive="${tmpdir}/${filename}"
  cached="${CACHE_DIR}/binaries/${filename}"
  if [[ -f "$cached" ]]; then
    info "using cache: binaries/${filename}"
    cp "$cached" "$archive"
  else
    curl -fsSL "$url" -o "$archive"
  fi
  unzip -q "$archive" -d "$tmpdir"
  install -m 0755 "${tmpdir}/yazi-${target}/yazi" "$dest"
  if [[ -f "${tmpdir}/yazi-${target}/ya" ]]; then
    install -m 0755 "${tmpdir}/yazi-${target}/ya" "${HOME}/.local/bin/ya"
  fi
  rm -rf "$tmpdir"
  success "yazi installed -> ${dest}"
}

ensure_login_bashrc() {
  local profile="${HOME}/.bash_profile"
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[dry-run] ensure ${profile} sources ~/.bashrc"
    return 0
  fi
  if [[ -f "$profile" ]] && grep -q 'bashrc' "$profile"; then
    return 0
  fi
  if [[ -f "$profile" ]]; then
    printf '\n[[ -f ~/.bashrc ]] && . ~/.bashrc\n' >>"$profile"
  else
    printf '[[ -f ~/.bashrc ]] && . ~/.bashrc\n' >"$profile"
  fi
  success "login shell will source ~/.bashrc"
}

install_tmux_plugins() {
  local install_script="${HOME}/.tmux/plugins/tpm/bin/install_plugins"
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[dry-run] install TPM plugins via detached tmux session"
    return 0
  fi
  if [[ ! -x "$install_script" ]]; then
    warn "TPM install_plugins missing; start tmux and press Ctrl-Space I"
    return 0
  fi
  if ! command -v tmux >/dev/null 2>&1; then
    warn "tmux not on PATH; skip TPM plugin install"
    return 0
  fi

  step "install TPM plugins ..."
  export TERM="${TERM:-xterm-256color}"
  tmux new-session -d -s devtools-bootstrap
  "$install_script"
  tmux kill-session -t devtools-bootstrap >/dev/null 2>&1 || true
  tmux kill-server >/dev/null 2>&1 || true
  success "TPM plugins installed"
}

run_module() {
  local script="$1"
  shift
  require_module "$script"
  if [[ "$DRY_RUN" == "true" ]]; then
    case "$script" in
      */editors/nvim/setup.sh|*/agents/*/setup.sh)
        info "[dry-run] ${script} $*"
        return 0
        ;;
    esac
    bash "$script" --dry-run "$@"
    return 0
  fi
  bash "$script" "$@"
}

agent_cli_present() {
  local bin
  for bin in "$@"; do
    if command -v "$bin" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

run_agent_install() {
  local script="$1"
  shift
  require_module "$script"
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[dry-run] ${script} install && ${script} sync"
    return 0
  fi
  if ! bash "$script" install; then
    if ! agent_cli_present "$@"; then
      error "agent CLI missing after install: $*"
      exit 1
    fi
    warn "agent install reported errors (plugins may need login): ${script}"
  fi
  bash "$script" sync || warn "agent sync failed; continuing: ${script}"
}

strip_agent_keys() {
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[dry-run] remove ~/.claude/.profile-keys ~/.codex/.profile-keys"
    return 0
  fi
  rm -f "${HOME}/.claude/.profile-keys" "${HOME}/.codex/.profile-keys"
}

main() {
  export HOME="${HOME:-/home/admin}"
  export USER="${USER:-admin}"
  export DEVTOOLS_CACHE_DIR="$CACHE_DIR"
  export NVIM_SETUP_STRICT="${NVIM_SETUP_STRICT:-1}"
  export TERM="${TERM:-xterm-256color}"
  export GIT_TERMINAL_PROMPT=0
  export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
  mkdir -p "${HOME}/.local/bin" "${HOME}/.config" "${HOME}/.cache/nvim" "${HOME}/.local/share/nvim"

  info "devtools Alinux 3 image bootstrap"
  info "HOME=${HOME} ROOT=${ROOT} dry-run=${DRY_RUN}"

  require_module "${ROOT}/shell/bash/setup.sh"
  require_module "${ROOT}/tools/git/setup.sh"
  require_module "${ROOT}/editors/vim/setup.sh"
  require_module "${ROOT}/editors/nvim/setup.sh"
  require_module "${ROOT}/terminal/tmux/setup.sh"
  require_module "${ROOT}/terminal/yazi/setup.sh"
  require_module "${ROOT}/tools/bazel/setup.sh"
  require_module "${ROOT}/languages/go/setup.sh"
  require_module "${ROOT}/languages/java/setup.sh"
  require_module "${ROOT}/agents/claude/setup.sh"
  require_module "${ROOT}/agents/codex/setup.sh"
  require_module "${ROOT}/agents/cursor-agent/setup.sh"
  require_module "${ROOT}/agents/cookbook/setup.sh"

  export SDKMAN_AUTO_ANSWER="${SDKMAN_AUTO_ANSWER:-true}"
  export npm_config_prefix="${npm_config_prefix:-${HOME}/.local}"

  install_lazygit
  install_delta
  install_bat
  install_rg
  install_yazi
  ensure_login_bashrc

  step "bash plugins (ble / fzf / zoxide / starship)"
  run_module "${ROOT}/shell/bash/setup.sh"

  step "git setup (delta / gh / subcommands / recommended config)"
  run_module "${ROOT}/tools/git/setup.sh" --skip-identity --skip-delta

  step "vim"
  run_module "${ROOT}/editors/vim/setup.sh" --upgrade

  step "nvim"
  run_module "${ROOT}/editors/nvim/setup.sh"

  step "tmux"
  run_module "${ROOT}/terminal/tmux/setup.sh" --upgrade
  install_tmux_plugins

  step "yazi config"
  run_module "${ROOT}/terminal/yazi/setup.sh"

  step "bazel"
  run_module "${ROOT}/tools/bazel/setup.sh"

  step "go"
  run_module "${ROOT}/languages/go/setup.sh"

  step "java"
  run_module "${ROOT}/languages/java/setup.sh"

  step "agent CLIs (install + sync, no API keys)"
  run_agent_install "${ROOT}/agents/claude/setup.sh" claude
  run_agent_install "${ROOT}/agents/codex/setup.sh" codex
  run_agent_install "${ROOT}/agents/cursor-agent/setup.sh" agent cursor-agent
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[dry-run] ${ROOT}/agents/cookbook/setup.sh sync --copy --target all"
  else
    bash "${ROOT}/agents/cookbook/setup.sh" sync --copy --target all \
      || warn "cookbook sync failed; continuing"
  fi
  strip_agent_keys

  success "image bootstrap complete"
}

main "$@"
