#!/usr/bin/env bash
# Java 环境安装脚本
# 用途：SDKMan + JDK 21 + Maven + Gradle

set -euo pipefail

if [[ "${BASH_VERSINFO[0]}" -lt 3 ]]; then
  echo "ERROR: 此脚本需要 bash 3.2 或更高版本" >&2; exit 1
fi

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}▶ $*${NC}"; }

is_installed() { command -v "$1" &>/dev/null; }

JDK_VERSION="${JDK_VERSION:-21.0.5-tem}"
OS="$(uname -s)"
ARCH="$(uname -m)"
SDKMAN_DIR="${SDKMAN_DIR:-$HOME/.sdkman}"

usage() {
  cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") [选项]

${BOLD}选项:${NC}
  -h, --help              显示此帮助
  --dry-run               预览，不实际安装
  --skip-maven            跳过 Maven 安装
  --skip-gradle           跳过 Gradle 安装
  --jdk-version <ver>     指定 JDK 版本（默认: ${JDK_VERSION}）

${BOLD}安装内容:${NC}
  SDKMan         Java SDK 版本管理器（跨平台）
  JDK ${JDK_VERSION}   Eclipse Temurin LTS（通过 SDKMan）
  Maven          构建工具（通过 SDKMan）
  Gradle         构建工具（通过 SDKMan）

${BOLD}示例:${NC}
  $(basename "$0")
  $(basename "$0") --skip-gradle
  $(basename "$0") --jdk-version 21.0.5-graalce

EOF
}

# SDKMAN scripts read optional positional params and env vars without
# defaults. Under `set -u` (this script and the alinux3 image bootstrap)
# that aborts (SDKMAN_CANDIDATES_API, $3 in sdkman-install.sh).
source_sdkman_init() {
  [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] || return 1
  set +u
  # shellcheck source=/dev/null
  source "$SDKMAN_DIR/bin/sdkman-init.sh"
  set -u
}

run_sdk() {
  local rc=0
  source_sdkman_init || return 1
  set +u
  sdk "$@" && rc=0 || rc=$?
  set -u
  return "$rc"
}

install_sdkman() {
  step "SDKMan 安装"

  if source_sdkman_init; then
    success "SDKMan 已安装：$(run_sdk version 2>/dev/null | head -1 || echo 'unknown')"
    return 0
  fi

  # 检查依赖
  if ! is_installed curl; then
    error "需要 curl，请先运行 OS 初始化脚本"
    exit 1
  fi
  if ! is_installed zip; then
    case "$OS" in
      Darwin)  brew install zip ;;
      Linux)
        if is_installed apt-get; then sudo apt-get install -y zip unzip;
        elif is_installed dnf; then sudo dnf install -y zip unzip;
        elif is_installed yum; then sudo yum install -y zip unzip; fi ;;
    esac
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将安装 SDKMan"
    return 0
  fi

  info "正在安装 SDKMan..."
  curl -s "https://get.sdkman.io" | bash

  if source_sdkman_init; then
    success "SDKMan 安装完成"
  else
    error "SDKMan 安装失败"
    exit 1
  fi
}

configure_sdkman_shell() {
  local rc_file marker='# SDKMan init (added by devtools/languages/java/setup.sh)'

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将配置 SDKMan 到 ~/.bashrc 和 ~/.zshrc"
    return 0
  fi

  touch "$HOME/.bashrc"
  for rc_file in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ -f "$rc_file" ]] || continue
    if grep -qF "$marker" "$rc_file" 2>/dev/null; then
      info "SDKMan 初始化已在 $rc_file 中，跳过"
      continue
    fi
    cat >> "$rc_file" <<'RCBLOCK'

# SDKMan init (added by devtools/languages/java/setup.sh)
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
RCBLOCK
    success "SDKMan 初始化已写入 $rc_file"
  done
}

sdk_install_if_missing() {
  local candidate="$1"
  local version="$2"
  local display="${3:-$candidate $version}"

  if ! source_sdkman_init; then
    warn "sdk 命令未找到，跳过 $display 安装"
    return 0
  fi

  if [[ -d "$SDKMAN_DIR/candidates/${candidate}/current" ]]; then
    success "$display 已安装"
    return 0
  fi

  if [[ "$version" != "latest" && -n "$version" ]] && \
     run_sdk list "$candidate" 2>/dev/null | grep -q "* $version\|> $version"; then
    success "$display 已安装"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将安装 $display"
    return 0
  fi

  info "正在安装 $display..."
  # SDKMAN 5.x rejects the literal version "latest"; omit it for the default.
  if [[ "$version" == "latest" || -z "$version" ]]; then
    run_sdk install "$candidate" < /dev/null
  else
    run_sdk install "$candidate" "$version" < /dev/null
  fi
  success "$display 安装完成"
}

install_jdk() {
  step "JDK ${JDK_VERSION} 安装"

  if is_installed java; then
    local java_ver
    java_ver=$(java -version 2>&1 | head -1)
    success "Java 已安装：$java_ver"
    info "如需管理多版本，使用 sdk list java 和 sdk use java <version>"
    return 0
  fi

  sdk_install_if_missing "java" "$JDK_VERSION" "JDK ${JDK_VERSION} (Eclipse Temurin)"
}

install_maven() {
  step "Maven 安装"
  sdk_install_if_missing "maven" "latest" "Maven"
}

install_gradle() {
  step "Gradle 安装"
  sdk_install_if_missing "gradle" "latest" "Gradle"
}

post_install_notes() {
  step "安装后说明"
  echo -e "  ${YELLOW}激活 SDKMan${NC}："
  echo -e "    source ~/.zshrc    # 或重开终端"
  echo -e ""
  echo -e "  ${YELLOW}验证安装${NC}："
  echo -e "    java -version"
  echo -e "    mvn --version"
  echo -e "    gradle --version"
  echo -e ""
  echo -e "  ${YELLOW}SDKMan 常用命令${NC}："
  echo -e "    sdk list java              # 查看可用 JDK 版本"
  echo -e "    sdk install java 21-graalce # 安装 GraalVM"
  echo -e "    sdk use java 21.0.5-tem    # 临时切换版本"
  echo -e "    sdk default java <version> # 设置默认版本"
  echo -e ""
  echo -e "  ${YELLOW}IDE 集成${NC}："
  echo -e "    VS Code: 安装 Extension Pack for Java"
  echo -e "    Neovim: jdtls（通过 Mason）"
  echo -e ""
}

main() {
  DRY_RUN=false
  SKIP_MAVEN=false
  SKIP_GRADLE=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)      usage; exit 0 ;;
      --dry-run)      DRY_RUN=true ;;
      --skip-maven)   SKIP_MAVEN=true ;;
      --skip-gradle)  SKIP_GRADLE=true ;;
      --jdk-version)
        [[ -z "${2:-}" ]] && { error "--jdk-version 需要值"; exit 1; }
        JDK_VERSION="$2"; shift ;;
      *) error "未知参数: $1"; usage; exit 1 ;;
    esac
    shift
  done

  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║   Java 环境安装                      ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"
  info "OS: $OS  ARCH: $ARCH  JDK 目标版本: $JDK_VERSION"
  [[ "$DRY_RUN" == true ]] && warn "DRY-RUN 模式，不实际安装"

  install_sdkman
  configure_sdkman_shell
  install_jdk
  $SKIP_MAVEN  || install_maven
  $SKIP_GRADLE || install_gradle

  post_install_notes
  echo -e "\n${GREEN}${BOLD}✓ Java 环境安装完成！${NC}\n"
}

main "$@"
