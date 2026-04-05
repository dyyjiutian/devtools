#!/usr/bin/env bash
# Bazel 编译环境安装脚本
# 通过 Bazelisk 管理 Bazel 版本，默认使用 Bazel 9
# 同时安装配套工具：buildifier、starpls
# 支持 macOS（Homebrew）和 Linux（二进制下载）

set -euo pipefail

# ─── 颜色定义 ────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}▶ $*${NC}"; }

# ─── 默认 Bazel 版本 ─────────────────────────────────────────────────────────
DEFAULT_BAZEL_VERSION="${DEFAULT_BAZEL_VERSION:-9.0.0}"

# ─── 用法说明 ────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") [选项]

${BOLD}说明:${NC}
  通过 Bazelisk 安装 Bazel 编译环境，以及配套的开发工具。
  支持 macOS（Homebrew）和 Linux（二进制下载），可重复执行。

${BOLD}选项:${NC}
  -h, --help              显示此帮助信息并退出
  --bazel-version <ver>   指定默认 Bazel 版本（默认: ${DEFAULT_BAZEL_VERSION}）
  --skip-bazelisk         跳过 Bazelisk 安装
  --skip-buildifier       跳过 Buildifier 安装
  --skip-starpls          跳过 Starpls 安装
  --skip-completion       跳过 Shell 补全配置
  --dry-run               预览操作，不实际执行

${BOLD}安装内容:${NC}
  bazelisk      - Bazel 版本管理器（替代 bazel 命令）
  buildifier    - BUILD/Starlark 文件格式化工具
  starpls       - Starlark 语言服务器（LSP，用于编辑器支持）

${BOLD}配置:${NC}
  ~/.bazeliskrc 中写入 USE_BAZEL_VERSION=${DEFAULT_BAZEL_VERSION}，使 bazelisk 默认使用指定版本
  ~/.config/bazel/ 存放 bash/zsh 补全脚本
  ~/.bashrc 和 ~/.zshrc 中写入补全配置

${BOLD}示例:${NC}
  $(basename "$0")                          # 完整安装
  $(basename "$0") --bazel-version 8.0.0   # 使用 Bazel 8 作为默认版本
  $(basename "$0") --skip-starpls           # 跳过 starpls 安装
  $(basename "$0") --dry-run                # 预览安装步骤

EOF
}

# ─── 工具函数 ────────────────────────────────────────────────────────────────
is_installed() {
  command -v "$1" &>/dev/null
}

run_or_dry() {
  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] $*"
  else
    "$@"
  fi
}

# 向文件追加内容，若标记行已存在则跳过（幂等）
append_if_absent() {
  local file="$1"
  local marker="$2"
  local content="$3"

  if grep -qF "$marker" "$file" 2>/dev/null; then
    info "$(basename "$file") 中已存在 '${marker}'，跳过"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将写入 ${file}："
    echo "$content" | sed 's/^/  /'
  else
    printf '\n%s\n' "$content" >> "$file"
    success "已写入 ${file}"
  fi
}

# ─── OS / 架构检测 ───────────────────────────────────────────────────────────
detect_os() {
  local kernel
  kernel="$(uname -s)"
  case "$kernel" in
    Darwin) OS="macos" ;;
    Linux)  OS="linux" ;;
    *)
      error "不支持的操作系统: ${kernel}"
      exit 1
      ;;
  esac
}

detect_arch() {
  local machine
  machine="$(uname -m)"
  case "$machine" in
    x86_64)           ARCH="amd64" ;;
    aarch64|arm64)    ARCH="arm64" ;;
    *)
      error "不支持的 CPU 架构: ${machine}"
      exit 1
      ;;
  esac
}

# ─── Linux 二进制安装目录 ─────────────────────────────────────────────────────
LINUX_BIN_DIR="$HOME/.local/bin"

ensure_linux_bin_dir() {
  if [[ ! -d "$LINUX_BIN_DIR" ]]; then
    run_or_dry mkdir -p "$LINUX_BIN_DIR"
  fi
  # 确保 ~/.local/bin 在 PATH 中（写入 ~/.bashrc 和 ~/.zshrc）
  local path_line='export PATH="$HOME/.local/bin:$PATH"'
  local marker='# ~/.local/bin PATH'
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ -f "$rc" ]] || continue
    append_if_absent "$rc" "$marker" "${marker}
${path_line}"
  done
}

# 从 GitHub Releases 下载二进制文件
download_binary() {
  local url="$1"
  local dest="$2"
  local desc="${3:-binary}"

  if [[ -f "$dest" ]]; then
    success "${desc} 已存在于 ${dest}，跳过下载"
    return 0
  fi

  info "正在下载 ${desc}..."
  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] curl -fsSL ${url} -o ${dest}"
    info "[dry-run] chmod +x ${dest}"
  else
    curl -fsSL "$url" -o "$dest"
    chmod +x "$dest"
    success "${desc} 已下载至 ${dest}"
  fi
}

# ─── Homebrew 辅助（macOS）────────────────────────────────────────────────────
check_brew() {
  if ! is_installed brew; then
    error "未找到 Homebrew，请先安装：https://brew.sh"
    exit 1
  fi
}

is_brew_installed() {
  brew list --formula "$1" &>/dev/null 2>&1
}

brew_install() {
  local pkg="$1"
  local desc="${2:-$pkg}"
  if is_brew_installed "$pkg"; then
    success "${desc} 已安装（$(brew list --versions "$pkg")），跳过"
  else
    info "正在安装 ${desc}..."
    run_or_dry brew install "$pkg" && success "${desc} 安装完成"
  fi
}

# ─── 安装 Bazelisk ───────────────────────────────────────────────────────────
install_bazelisk() {
  step "Bazelisk 安装"

  if [[ "$OS" == "macos" ]]; then
    # 检查是否已安装原生 bazel（会与 bazelisk 冲突）
    if is_brew_installed bazel; then
      warn "检测到已通过 Homebrew 安装了 bazel，它与 bazelisk 冲突"
      warn "请先卸载：brew uninstall bazel"
      exit 1
    fi
    brew_install bazelisk "Bazelisk（Bazel 版本管理器）"
  else
    ensure_linux_bin_dir
    local dest="${LINUX_BIN_DIR}/bazelisk"
    local url="https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-${ARCH}"
    download_binary "$url" "$dest" "Bazelisk"

    # 在 ~/.local/bin 下创建 bazel -> bazelisk 软链接（幂等）
    local bazel_link="${LINUX_BIN_DIR}/bazel"
    if [[ ! -L "$bazel_link" ]]; then
      run_or_dry ln -sf "$dest" "$bazel_link"
      success "已创建 bazel -> bazelisk 软链接"
    else
      success "bazel 软链接已存在，跳过"
    fi
  fi

  if [[ "$DRY_RUN" != true ]] && is_installed bazelisk; then
    info "bazelisk 版本：$(bazelisk version 2>/dev/null | head -1 || echo 'unknown')"
  fi
}

# ─── 配置默认 Bazel 版本（~/.bazeliskrc）────────────────────────────────────
configure_bazeliskrc() {
  step "配置默认 Bazel 版本（~/.bazeliskrc）"

  local rc="$HOME/.bazeliskrc"
  local key="USE_BAZEL_VERSION"
  local new_line="${key}=${BAZEL_VERSION}"

  if grep -q "^${key}=" "$rc" 2>/dev/null; then
    local current
    current="$(grep "^${key}=" "$rc" | head -1)"
    if [[ "$current" == "$new_line" ]]; then
      success "~/.bazeliskrc 已配置 ${new_line}，跳过"
    else
      info "更新 ~/.bazeliskrc：${current} → ${new_line}"
      if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] sed 替换 ${rc} 中的 ${key} 行"
      else
        # macOS sed 需要 -i '' ，Linux sed 用 -i
        if [[ "$OS" == "macos" ]]; then
          sed -i '' "s|^${key}=.*|${new_line}|" "$rc"
        else
          sed -i "s|^${key}=.*|${new_line}|" "$rc"
        fi
        success "已更新 ~/.bazeliskrc：${new_line}"
      fi
    fi
  else
    if [[ "$DRY_RUN" == true ]]; then
      info "[dry-run] 将写入 ~/.bazeliskrc：${new_line}"
    else
      echo "${new_line}" >> "$rc"
      success "已写入 ~/.bazeliskrc：${new_line}"
    fi
  fi
}

# ─── 安装 Buildifier ─────────────────────────────────────────────────────────
install_buildifier() {
  step "Buildifier 安装"

  if [[ "$OS" == "macos" ]]; then
    brew_install buildifier "Buildifier（BUILD 文件格式化）"
  else
    ensure_linux_bin_dir
    local dest="${LINUX_BIN_DIR}/buildifier"
    local url="https://github.com/bazelbuild/buildtools/releases/latest/download/buildifier-linux-${ARCH}"
    download_binary "$url" "$dest" "Buildifier"
  fi

  if [[ "$DRY_RUN" != true ]] && is_installed buildifier; then
    info "buildifier 版本：$(buildifier --version 2>/dev/null || echo 'unknown')"
  fi
}

# ─── 安装 Starpls ─────────────────────────────────────────────────────────────
install_starpls() {
  step "Starpls 安装"

  if [[ "$OS" == "macos" ]]; then
    local tap="withered-magic/brew"
    local formula="withered-magic/brew/starpls"

    if ! brew tap | grep -qF "withered-magic/brew"; then
      if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] brew tap ${tap}"
      else
        info "正在添加 Homebrew tap：${tap}..."
        brew tap "$tap"
        success "已添加 tap：${tap}"
      fi
    else
      info "Homebrew tap ${tap} 已存在"
    fi

    if brew list starpls &>/dev/null 2>&1; then
      success "starpls 已安装（$(brew list --versions starpls)），跳过"
    else
      info "正在安装 starpls（Starlark 语言服务器）..."
      run_or_dry brew install "$formula" && success "starpls 安装完成"
    fi
  else
    ensure_linux_bin_dir
    local dest="${LINUX_BIN_DIR}/starpls"
    local url="https://github.com/withered-magic/starpls/releases/latest/download/starpls-linux-${ARCH}"
    download_binary "$url" "$dest" "Starpls"
  fi

  if [[ "$DRY_RUN" != true ]] && is_installed starpls; then
    info "starpls 路径：$(which starpls)"
  fi
}

# ─── Shell 补全配置 ──────────────────────────────────────────────────────────
BAZEL_COMPLETION_DIR="$HOME/.config/bazel"

# 下载补全脚本
download_completion_scripts() {
  local version="$BAZEL_VERSION"
  local base_url="https://raw.githubusercontent.com/bazelbuild/bazel/${version}/scripts"

  if [[ "$DRY_RUN" != true ]]; then
    mkdir -p "$BAZEL_COMPLETION_DIR"
  else
    info "[dry-run] mkdir -p ${BAZEL_COMPLETION_DIR}"
  fi

  # bash 补全
  local bash_dest="${BAZEL_COMPLETION_DIR}/bazel-complete.bash"
  if [[ -f "$bash_dest" ]]; then
    success "bash 补全脚本已存在（${bash_dest}），跳过下载"
  else
    info "正在下载 bash 补全脚本（bazel ${version}）..."
    if [[ "$DRY_RUN" == true ]]; then
      info "[dry-run] curl -fsSL ${base_url}/bazel-complete.bash -o ${bash_dest}"
    else
      if curl -fsSL "${base_url}/bazel-complete.bash" -o "$bash_dest" 2>/dev/null; then
        success "bash 补全脚本已下载至 ${bash_dest}"
      else
        warn "bash 补全脚本下载失败（版本 ${version} 可能不存在），尝试 master 分支"
        curl -fsSL "https://raw.githubusercontent.com/bazelbuild/bazel/master/scripts/bazel-complete.bash" \
          -o "$bash_dest" || warn "bash 补全脚本下载失败，跳过"
      fi
    fi
  fi

  # zsh 补全（macOS brew 已有，但仍下载到统一目录作备份）
  local zsh_dest="${BAZEL_COMPLETION_DIR}/_bazel"
  if [[ -f "$zsh_dest" ]]; then
    success "zsh 补全脚本已存在（${zsh_dest}），跳过下载"
  else
    info "正在下载 zsh 补全脚本（bazel ${version}）..."
    if [[ "$DRY_RUN" == true ]]; then
      info "[dry-run] curl -fsSL ${base_url}/zsh_completion/_bazel -o ${zsh_dest}"
    else
      if curl -fsSL "${base_url}/zsh_completion/_bazel" -o "$zsh_dest" 2>/dev/null; then
        success "zsh 补全脚本已下载至 ${zsh_dest}"
      else
        warn "zsh 补全脚本下载失败（版本 ${version} 可能不存在），尝试 master 分支"
        curl -fsSL "https://raw.githubusercontent.com/bazelbuild/bazel/master/scripts/zsh_completion/_bazel" \
          -o "$zsh_dest" || warn "zsh 补全脚本下载失败，跳过"
      fi
    fi
  fi
}

setup_bash_completion() {
  step "Bash 补全配置"

  local bashrc="$HOME/.bashrc"
  local marker="# Bazel bash completion"
  local block="${marker}
[ -f \"${BAZEL_COMPLETION_DIR}/bazel-complete.bash\" ] && source \"${BAZEL_COMPLETION_DIR}/bazel-complete.bash\""

  # 确保 ~/.bashrc 存在
  [[ -f "$bashrc" ]] || touch "$bashrc"

  append_if_absent "$bashrc" "$marker" "$block"
}

setup_zsh_completion() {
  step "Zsh 补全配置"

  local zshrc="$HOME/.zshrc"
  local marker="# Bazel zsh completion"

  # macOS + brew：bazelisk 通过 brew 安装时 _bazel 已在 /opt/homebrew/share/zsh/site-functions/
  # 同时也将 ~/.config/bazel 加入 fpath，作为跨平台统一方式
  local block="${marker}
if [[ -d \"${BAZEL_COMPLETION_DIR}\" ]]; then
  fpath=(\"${BAZEL_COMPLETION_DIR}\" \$fpath)
fi
autoload -Uz compinit && compinit -C"

  # macOS brew 路径额外提示
  if [[ "$OS" == "macos" ]] && [[ -d /opt/homebrew/share/zsh/site-functions ]]; then
    info "检测到 Homebrew zsh site-functions，_bazel 补全已由 brew 安装"
  fi

  append_if_absent "$zshrc" "$marker" "$block"
}

setup_completion() {
  download_completion_scripts
  setup_bash_completion
  setup_zsh_completion
}

# ─── 安装后提示 ──────────────────────────────────────────────────────────────
post_install_notes() {
  step "安装后说明"

  echo -e ""
  echo -e "  ${YELLOW}Bazelisk${NC}: 已接管 bazel 命令，根据 ~/.bazeliskrc 或工作区的"
  echo -e "    .bazelversion 文件自动下载并调用对应版本的 Bazel。"
  echo -e ""
  echo -e "  ${YELLOW}默认版本${NC}: Bazel ${BAZEL_VERSION}（通过 ~/.bazeliskrc 中的 USE_BAZEL_VERSION）"
  echo -e "    优先级（从高到低）："
  echo -e "      1. USE_BAZEL_VERSION 环境变量"
  echo -e "      2. 工作区 .bazelversion 文件"
  echo -e "      3. ~/.bazeliskrc"
  echo -e "    可在项目根目录创建 .bazelversion 覆盖全局设置："
  echo -e "      ${BOLD}echo '9.0.0' > .bazelversion${NC}"
  echo -e ""
  echo -e "  ${YELLOW}Buildifier${NC}: BUILD 和 .bzl 文件格式化工具"
  echo -e "    用法: buildifier BUILD.bazel"
  echo -e "    递归格式化: find . -name '*.bazel' -o -name '*.bzl' | xargs buildifier"
  echo -e ""
  echo -e "  ${YELLOW}Starpls${NC}: Starlark 语言服务器（LSP）"
  echo -e "    在 Cursor/VSCode 中安装 Bazel 扩展后，配置 settings.json："
  echo -e "      ${BOLD}\"bazel.lsp.command\": \"starpls\"${NC}"
  echo -e ""
  echo -e "  ${YELLOW}Shell 补全${NC}: 补全脚本已写入 ${BAZEL_COMPLETION_DIR}/"
  echo -e "    立即生效："
  echo -e "      ${BOLD}source ~/.bashrc${NC}   # bash"
  echo -e "      ${BOLD}source ~/.zshrc${NC}    # zsh"
  echo -e ""
  echo -e "  ${YELLOW}验证安装${NC}:"
  echo -e "    bazel version     # 查看当前使用的 Bazel 版本"
  echo -e "    buildifier -h     # 查看 buildifier 帮助"
  echo -e "    starpls --help    # 查看 starpls 帮助"
  echo -e ""
}

# ─── 主入口 ──────────────────────────────────────────────────────────────────
main() {
  local skip_bazelisk=false
  local skip_buildifier=false
  local skip_starpls=false
  local skip_completion=false
  DRY_RUN=false
  BAZEL_VERSION="$DEFAULT_BAZEL_VERSION"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --bazel-version)
        BAZEL_VERSION="$2"
        shift
        ;;
      --skip-bazelisk)
        skip_bazelisk=true
        ;;
      --skip-buildifier)
        skip_buildifier=true
        ;;
      --skip-starpls)
        skip_starpls=true
        ;;
      --skip-completion)
        skip_completion=true
        ;;
      --dry-run)
        DRY_RUN=true
        ;;
      *)
        error "未知参数: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done

  detect_os
  detect_arch

  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║   Bazel 编译环境安装脚本             ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"
  info "操作系统: ${OS} / 架构: ${ARCH}"

  if [[ "$DRY_RUN" == true ]]; then
    warn "Dry-run 模式：仅预览操作，不实际执行"
  fi

  if [[ "$OS" == "macos" ]]; then
    check_brew
  fi

  $skip_bazelisk   || install_bazelisk
  configure_bazeliskrc
  $skip_buildifier || install_buildifier
  $skip_starpls    || install_starpls
  $skip_completion || setup_completion

  post_install_notes

  echo -e "\n${GREEN}${BOLD}✓ Bazel 编译环境安装完成！${NC}\n"
}

main "$@"
