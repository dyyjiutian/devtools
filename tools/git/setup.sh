#!/usr/bin/env bash
# One-shot Git setup: orchestrates git-delta install plus the three helper
# scripts under scripts/ (sub-command.sh, config.sh, alias.sh).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
CACHE_DIR="${DEVTOOLS_CACHE_DIR:-${SCRIPT_DIR}/../../cache}"
OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"
DELTA_VERSION="0.19.2"
DELTA_TARGET="x86_64-unknown-linux-musl"
DELTA_ARCHIVE="delta-${DELTA_VERSION}-${DELTA_TARGET}.tar.gz"
DELTA_ARCHIVE_SHA256="f1ea01ca7728ce3462debc359f39dfc7cbbc1a63224b71fefabf92042864aa1b"
DELTA_RELEASE_URL="https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/${DELTA_ARCHIVE}"
DRY_RUN=false
SKIP_ALIAS=false
SKIP_CONFIG=false
SKIP_DELTA=false
SKIP_GH=false
SKIP_IDENTITY=false
SKIP_SUBCMD=false

info()    { echo -e "\033[34m[INFO]\033[0m $1"; }
success() { echo -e "\033[32m[OK]\033[0m $1"; }
warn()    { echo -e "\033[33m[WARN]\033[0m $1"; }
error()   { echo -e "\033[31m[ERROR]\033[0m $1"; }
step()    { echo -e "\033[36m[STEP]\033[0m $1"; }

show_help() {
  cat <<'EOF'
用法: ./setup.sh [选项]

一键配置 Git 开发环境（各步骤也可单独运行对应的 scripts/*.sh）:
  - 安装 GitHub CLI (gh)，用于 GitHub PR / issue / review 操作
  - 安装 git-delta 并配置为 diff/log/show pager
  - scripts/sub-command.sh：安装 git rb / bc / wc / review / sparse-clone 子命令到 ~/.local/bin
  - scripts/config.sh：写入推荐的 git 全局配置与性能/工作流优化
  - scripts/alias.sh：安装 gitroot（cd 到仓库根目录）

选项:
  -h, --help        显示帮助
  -d, --dry-run     试运行，只打印将要执行的操作
  --skip-delta      跳过 git-delta 安装
  --skip-gh         跳过 GitHub CLI (gh) 安装
  --skip-subcmd     跳过 git 子命令安装
  --skip-config     跳过 git config 配置
  --skip-identity   写入推荐 git config，但不设置 user.name / user.email
  --skip-alias      跳过 shell alias 配置

示例:
  ./setup.sh
  ./setup.sh --dry-run
  ./setup.sh --skip-delta --skip-gh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)     show_help; exit 0 ;;
    -d|--dry-run)  DRY_RUN=true; shift ;;
    --skip-alias)    SKIP_ALIAS=true; shift ;;
    --skip-config)   SKIP_CONFIG=true; shift ;;
    --skip-delta)    SKIP_DELTA=true; shift ;;
    --skip-gh)       SKIP_GH=true; shift ;;
    --skip-identity) SKIP_IDENTITY=true; shift ;;
    --skip-subcmd)   SKIP_SUBCMD=true; shift ;;
    *) error "未知选项: $1"; show_help; exit 1 ;;
  esac
done

run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '[DRY RUN] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

try_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    run_cmd "$@"
    return 0
  fi
  "$@"
}

require_git() {
  if ! command -v git &>/dev/null; then
    error "需要 git，请先安装 Git"
    exit 1
  fi
}

linux_release_info() {
  local ID="" VERSION_ID="" VERSION_CODENAME="" UBUNTU_CODENAME=""
  if [[ -r "$OS_RELEASE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$OS_RELEASE_FILE"
  fi
  printf '%s %s %s\n' \
    "${ID:-}" \
    "${VERSION_ID%%.*}" \
    "${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
}

try_delta_aliyun_apt() {
  local os_id os_major codename mirror source_entry source_list lists_dir tmpdir=""
  read -r os_id os_major codename < <(linux_release_info)
  case "$os_id" in
    ubuntu)
      mirror="https://mirrors.aliyun.com/ubuntu"
      source_entry="deb ${mirror}/ ${codename} main universe"
      ;;
    debian)
      mirror="https://mirrors.aliyun.com/debian"
      source_entry="deb ${mirror}/ ${codename} main"
      ;;
    *)
      return 1
      ;;
  esac
  [[ -n "$codename" ]] || return 1

  info "尝试阿里云 APT 镜像安装 git-delta: ${mirror}"
  if [[ "$DRY_RUN" == "true" ]]; then
    source_list="${TMPDIR:-/tmp}/devtools-git-delta.sources.list"
    lists_dir="${TMPDIR:-/tmp}/devtools-git-delta.apt-lists"
  else
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/git-delta-apt.XXXXXX")"
    source_list="${tmpdir}/sources.list"
    lists_dir="${tmpdir}/lists"
    mkdir -p "${lists_dir}/partial"
    printf '%s\n' "$source_entry" >"$source_list"
    trap 'rm -rf "$tmpdir"' EXIT
    trap 'exit 130' HUP INT TERM
  fi

  if try_cmd sudo apt-get \
      -o "Dir::Etc::sourcelist=${source_list}" \
      -o "Dir::Etc::sourceparts=-" \
      -o "Dir::State::lists=${lists_dir}" \
      -o "APT::Get::List-Cleanup=0" update \
    && try_cmd sudo apt-get \
      -o "Dir::Etc::sourcelist=${source_list}" \
      -o "Dir::Etc::sourceparts=-" \
      -o "Dir::State::lists=${lists_dir}" \
      -o "APT::Get::List-Cleanup=0" install -y git-delta; then
    if [[ -n "$tmpdir" ]]; then
      rm -rf "$tmpdir"
      trap - EXIT HUP INT TERM
    fi
    return 0
  fi

  if [[ -n "$tmpdir" ]]; then
    rm -rf "$tmpdir"
    trap - EXIT HUP INT TERM
  fi
  return 1
}

try_delta_aliyun_epel() {
  local pkg_manager="$1" os_id os_major codename repo_dir=""
  local repo_file
  read -r os_id os_major codename < <(linux_release_info)
  case "$os_id" in
    rhel|centos|rocky|almalinux) ;;
    alinux)
      [[ "$os_major" == "3" ]] || return 1
      os_major=8
      ;;
    *) return 1 ;;
  esac
  case "$os_major" in
    8|9) ;;
    *) return 1 ;;
  esac

  info "尝试阿里云 EPEL ${os_major} 镜像安装 git-delta: https://mirrors.aliyun.com/epel/${os_major}/Everything"
  if [[ "$DRY_RUN" == "true" ]]; then
    repo_dir="${TMPDIR:-/tmp}/devtools-git-delta.repos.d"
  else
    repo_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-delta-epel.XXXXXX")"
    repo_file="${repo_dir}/devtools-epel.repo"
    cat >"$repo_file" <<EOF
[devtools-epel]
name=Temporary Alibaba Cloud EPEL ${os_major}
baseurl=https://mirrors.aliyun.com/epel/${os_major}/Everything/\$basearch/
enabled=1
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/epel/RPM-GPG-KEY-EPEL-${os_major}
EOF
    trap 'rm -rf "$repo_dir"' EXIT
    trap 'exit 130' HUP INT TERM
  fi

  if try_cmd sudo "$pkg_manager" \
      "--setopt=reposdir=${repo_dir}" \
      --disablerepo='*' \
      --enablerepo=devtools-epel \
      install -y git-delta; then
    if [[ "$DRY_RUN" == "false" ]]; then
      rm -rf "$repo_dir"
      trap - EXIT HUP INT TERM
    fi
    return 0
  fi

  if [[ "$DRY_RUN" == "false" ]]; then
    rm -rf "$repo_dir"
    trap - EXIT HUP INT TERM
  fi
  return 1
}

verify_delta_archive() {
  local archive="$1" actual
  if ! command -v sha256sum &>/dev/null; then
    warn "缺少 sha256sum，拒绝使用未校验的 git-delta 静态包"
    return 1
  fi
  actual="$(sha256sum "$archive" | awk '{print $1}')" || return 1
  [[ "$actual" == "$DELTA_ARCHIVE_SHA256" ]]
}

try_delta_centos7_static() {
  local arch="${DEVTOOLS_ARCH:-$(uname -m)}"
  local cache_archive="${CACHE_DIR}/binaries/${DELTA_ARCHIVE}"
  local archive="$cache_archive"
  local tmpdir delta_bin
  case "$arch" in
    x86_64|amd64) ;;
    *) return 1 ;;
  esac

  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/git-delta-static.XXXXXX")"
  trap 'rm -rf "$tmpdir"' EXIT
  trap 'exit 130' HUP INT TERM

  if [[ -f "$cache_archive" ]]; then
    info "使用本地缓存: binaries/${DELTA_ARCHIVE}"
    if ! verify_delta_archive "$cache_archive"; then
      warn "本地 git-delta 缓存 SHA-256 校验失败，拒绝安装并尝试上游下载"
      archive="${tmpdir}/${DELTA_ARCHIVE}"
    fi
  else
    archive="${tmpdir}/${DELTA_ARCHIVE}"
  fi

  if [[ "$archive" != "$cache_archive" ]]; then
    info "网络下载: ${DELTA_ARCHIVE}"
    if ! try_cmd curl -fsSL "$DELTA_RELEASE_URL" -o "$archive"; then
      warn "git-delta 静态包下载失败"
      rm -rf "$tmpdir"
      trap - EXIT HUP INT TERM
      return 1
    fi
  fi

  if [[ "$DRY_RUN" == "false" ]] && ! verify_delta_archive "$archive"; then
    warn "下载的 git-delta 静态包 SHA-256 校验失败，拒绝安装"
    rm -rf "$tmpdir"
    trap - EXIT HUP INT TERM
    return 1
  fi

  delta_bin="${tmpdir}/delta-${DELTA_VERSION}-${DELTA_TARGET}/delta"
  if ! try_cmd tar -xzf "$archive" -C "$tmpdir" \
      "delta-${DELTA_VERSION}-${DELTA_TARGET}/delta" \
    || ! try_cmd sudo install -m 0755 "$delta_bin" /usr/local/bin/delta; then
    warn "git-delta 静态包解压或安装失败"
    rm -rf "$tmpdir"
    trap - EXIT HUP INT TERM
    return 1
  fi

  rm -rf "$tmpdir"
  trap - EXIT HUP INT TERM
  success "git-delta ${DELTA_VERSION} 静态包安装完成"
  return 0
}

install_delta() {
  if [[ "$SKIP_DELTA" == "true" ]]; then
    info "跳过 git-delta 安装"
    return
  fi

  step "安装/检查 git-delta ..."
  if command -v delta &>/dev/null; then
    success "git-delta 已安装: $(delta --version | head -1)"
    return
  fi

  case "$(uname -s)" in
    Darwin)
      if ! command -v brew &>/dev/null; then
        warn "未找到 Homebrew，跳过 git-delta 安装。可手动执行: brew install git-delta"
        return
      fi
      if ! try_cmd brew install git-delta; then
        warn "git-delta 安装失败，继续执行后续 Git 配置"
        return
      fi
      ;;
    Linux)
      local os_id os_major codename
      read -r os_id os_major codename < <(linux_release_info)
      if [[ "$os_id" == "centos" && "$os_major" == "7" ]]; then
        if try_delta_centos7_static; then
          return
        fi
        warn "CentOS 7 静态包安装失败或架构不适用，尝试当前系统仓库"
      fi

      if command -v apt-get &>/dev/null; then
        if try_delta_aliyun_apt; then
          return
        fi
        warn "阿里云 APT 镜像安装失败，尝试当前系统仓库"
        if ! try_cmd sudo apt-get update || ! try_cmd sudo apt-get install -y git-delta; then
          warn "git-delta 安装失败，继续执行后续 Git 配置"
          return
        fi
      elif command -v dnf &>/dev/null; then
        if try_delta_aliyun_epel dnf; then
          return
        fi
        warn "阿里云 EPEL 镜像安装失败或不适用，尝试当前系统仓库"
        if ! try_cmd sudo dnf install -y git-delta; then
          warn "git-delta 安装失败，继续执行后续 Git 配置"
          return
        fi
      elif command -v yum &>/dev/null; then
        if try_delta_aliyun_epel yum; then
          return
        fi
        warn "阿里云 EPEL 镜像安装失败或不适用，尝试当前系统仓库"
        if ! try_cmd sudo yum install -y git-delta; then
          warn "git-delta 安装失败，继续执行后续 Git 配置"
          return
        fi
      else
        warn "未找到 apt、dnf 或 yum，跳过 git-delta 安装"
        warn "可手动安装后重跑本脚本以启用 delta 配置"
        return
      fi
      ;;
    *)
      warn "不支持的系统: $(uname -s)，跳过 git-delta 安装"
      return
      ;;
  esac

  if [[ "$DRY_RUN" == "false" ]]; then
    command -v delta &>/dev/null && success "git-delta 安装完成" || warn "git-delta 安装命令已执行，但当前 PATH 未找到 delta"
  fi
}

install_gh() {
  if [[ "$SKIP_GH" == "true" ]]; then
    info "跳过 GitHub CLI (gh) 安装"
    return
  fi

  step "安装/检查 GitHub CLI (gh) ..."
  if command -v gh &>/dev/null; then
    success "GitHub CLI 已安装: $(gh --version | head -1)"
    info "请执行: gh auth login"
    return
  fi

  case "$(uname -s)" in
    Darwin)
      if ! command -v brew &>/dev/null; then
        warn "未找到 Homebrew，跳过 GitHub CLI 安装。可手动执行: brew install gh"
        return
      fi
      if ! try_cmd brew install gh; then
        warn "GitHub CLI 安装失败，继续执行后续 Git 配置"
        return
      fi
      ;;
    Linux)
      if command -v apt-get &>/dev/null; then
        if ! try_cmd sudo apt-get update || ! try_cmd sudo apt-get install -y gh; then
          warn "GitHub CLI 安装失败，继续执行后续 Git 配置"
          return
        fi
      elif command -v dnf &>/dev/null; then
        if dnf --version 2>/dev/null | head -1 | grep -q '^5'; then
          if ! try_cmd sudo dnf install -y dnf5-plugins \
            || ! try_cmd sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo \
            || ! try_cmd sudo dnf install -y gh; then
            warn "GitHub CLI 安装失败，继续执行后续 Git 配置"
            return
          fi
        elif ! try_cmd sudo dnf install -y 'dnf-command(config-manager)' \
          || ! try_cmd sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo \
          || ! try_cmd sudo dnf install -y gh; then
          warn "GitHub CLI 安装失败，继续执行后续 Git 配置"
          return
        fi
        info "Aliyun 镜像站无 GitHub CLI RPM，仅使用官方源 cli.github.com"
      elif command -v yum &>/dev/null; then
        if ! try_cmd sudo yum install -y gh; then
          warn "GitHub CLI 安装失败，继续执行后续 Git 配置"
          return
        fi
      else
        warn "未找到 apt、dnf 或 yum，跳过 GitHub CLI 安装"
        warn "可手动安装 gh 后重跑本脚本以启用 GitHub git review 工作流"
        return
      fi
      ;;
    *)
      warn "不支持的系统: $(uname -s)，跳过 GitHub CLI 安装"
      return
      ;;
  esac

  if [[ "$DRY_RUN" == "true" ]]; then
    info "GitHub CLI 安装完成后，请执行: gh auth login"
  elif command -v gh &>/dev/null; then
    success "GitHub CLI 安装完成"
    info "请执行: gh auth login"
  else
    warn "GitHub CLI 安装命令已执行，但当前 PATH 未找到 gh"
  fi
}

install_subcommands() {
  if [[ "$SKIP_SUBCMD" == "true" ]]; then
    info "跳过 git 子命令安装"
    return
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    bash "$SCRIPTS_DIR/sub-command.sh" --dry-run
  else
    bash "$SCRIPTS_DIR/sub-command.sh"
  fi
}

run_config() {
  if [[ "$SKIP_CONFIG" == "true" ]]; then
    info "跳过 git config 配置"
    return
  fi
  step "写入 git config ..."
  local -a config_args=()
  if [[ "$DRY_RUN" == "true" ]]; then
    config_args+=(--dry-run)
  fi
  if [[ "$SKIP_IDENTITY" == "true" ]]; then
    config_args+=(--skip-identity)
  fi
  if [[ ${#config_args[@]} -gt 0 ]]; then
    bash "$SCRIPTS_DIR/config.sh" "${config_args[@]}"
  else
    bash "$SCRIPTS_DIR/config.sh"
  fi
}

install_aliases() {
  if [[ "$SKIP_ALIAS" == "true" ]]; then
    info "跳过 shell alias 配置"
    return
  fi
  step "安装 shell aliases ..."
  if [[ "$DRY_RUN" == "true" ]]; then
    run_cmd bash "$SCRIPTS_DIR/alias.sh"
  else
    bash "$SCRIPTS_DIR/alias.sh"
  fi
}

main() {
  info "Git 一键配置脚本"
  info "运行模式: $([[ "$DRY_RUN" == "true" ]] && echo "试运行" || echo "实际执行")"
  echo ""

  require_git
  install_delta
  install_gh
  install_subcommands
  run_config
  install_aliases

  echo ""
  success "Git 配置完成"
  echo ""
  echo "  验证命令:"
  echo "    git config --global --list --show-origin"
  echo "    git status"
  echo "    git rb --help / git bc --help / git wc --help / git review --help"
  echo ""
  echo "  若刚安装 gitroot alias 或子命令 PATH，请重新打开终端，或 source 当前 shell rc 文件。"
}

if [[ "${SETUP_NO_MAIN:-false}" != "true" && "${SETUP_NO_MAIN:-false}" != "1" ]]; then
  main
fi
