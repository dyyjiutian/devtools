#!/usr/bin/env bash
# 预下载所有离线安装包到 cache 目录
# 用法: ./download.sh [macos|linux|all]  （默认 all）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
BINARIES_DIR="${SCRIPT_DIR}/binaries"
FONTS_DIR="${SCRIPT_DIR}/fonts"

mkdir -p "$SCRIPTS_DIR" "$BINARIES_DIR" "$FONTS_DIR"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
BOLD=$'\033[1m'
NC=$'\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# 下载单个文件，已存在则跳过
download() {
  local url="$1"
  local dest="$2"
  if [[ -f "$dest" ]]; then
    info "已存在，跳过: $(basename "$dest")"
    return
  fi
  info "下载: $(basename "$dest") ..."
  if curl -fsSL "$url" -o "$dest"; then
    success "完成: $(basename "$dest")"
  else
    error "失败: $url"
    rm -f "$dest"
    return 1
  fi
}

download_macos() {
  echo -e "\n${BOLD}▶ macOS 所需文件${NC}"
  download \
    "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" \
    "${SCRIPTS_DIR}/homebrew-install.sh"
  download \
    "https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh" \
    "${SCRIPTS_DIR}/nvm-install.sh"
  download \
    "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" \
    "${SCRIPTS_DIR}/ohmyzsh-install.sh"
}

download_linux() {
  echo -e "\n${BOLD}▶ Linux 所需文件${NC}"

  # 安装脚本
  download \
    "https://download.docker.com/linux/centos/docker-ce.repo" \
    "${SCRIPTS_DIR}/docker-ce.repo"
  download \
    "https://rpm.nodesource.com/setup_20.x" \
    "${SCRIPTS_DIR}/nodesource-setup-20.x"
  download \
    "https://github.com/XTLS/Xray-install/raw/main/install-release.sh" \
    "${SCRIPTS_DIR}/install-release.sh"

  # 二进制包版本
  local yazi_version="0.3.3"
  local lazygit_version="0.44.1"
  local fzf_version="0.72.0"
  local zoxide_version="0.9.4"
  local starship_version="1.25.1"
  local nerd_fonts_version="3.3.0"
  local xray_version="26.3.27"
  local tmux_version="3.7b"

  # yazi (x86_64 / arm64) — musl 静态编译版，兼容 CentOS/RHEL 8（glibc 2.28）
  for arch in x86_64 aarch64; do
    download \
      "https://github.com/sxyazi/yazi/releases/download/v${yazi_version}/yazi-${arch}-unknown-linux-musl.zip" \
      "${BINARIES_DIR}/yazi-${arch}-unknown-linux-musl.zip"
  done

  # lazygit (x86_64 / arm64)
  for arch in x86_64 arm64; do
    download \
      "https://github.com/jesseduffield/lazygit/releases/download/v${lazygit_version}/lazygit_${lazygit_version}_Linux_${arch}.tar.gz" \
      "${BINARIES_DIR}/lazygit_${lazygit_version}_Linux_${arch}.tar.gz"
  done

  # fzf (x86_64 / arm64)
  for arch in linux_amd64 linux_arm64; do
    download \
      "https://github.com/junegunn/fzf/releases/download/v${fzf_version}/fzf-${fzf_version}-${arch}.tar.gz" \
      "${BINARIES_DIR}/fzf-${fzf_version}-${arch}.tar.gz"
  done

  # zoxide (x86_64 / arm64)
  for arch in x86_64-unknown-linux-musl aarch64-unknown-linux-musl; do
    download \
      "https://github.com/ajeetdsouza/zoxide/releases/download/v${zoxide_version}/zoxide-${zoxide_version}-${arch}.tar.gz" \
      "${BINARIES_DIR}/zoxide-${zoxide_version}-${arch}.tar.gz"
  done

  # Starship (x86_64 / arm64) — musl 静态编译版，适合兼容性较差的 ECS 系统
  for arch in x86_64-unknown-linux-musl aarch64-unknown-linux-musl; do
    download \
      "https://github.com/starship/starship/releases/download/v${starship_version}/starship-${arch}.tar.gz" \
      "${BINARIES_DIR}/starship-${arch}.tar.gz"
  done

  # Xray-core（tools/vpn/client/linux_setup.sh）
  for arch in 64 arm64-v8a arm32-v7a; do
    download \
      "https://github.com/XTLS/Xray-core/releases/download/v${xray_version}/Xray-linux-${arch}.zip" \
      "${BINARIES_DIR}/Xray-linux-${arch}-v${xray_version}.zip"
  done

  # tmux 源码包（terminal/tmux/setup.sh / os/linux 源码编译用）
  download \
    "https://github.com/tmux/tmux/releases/download/${tmux_version}/tmux-${tmux_version}.tar.gz" \
    "${BINARIES_DIR}/tmux-${tmux_version}.tar.gz"

  # Nerd Fonts Symbols Only — 架构无关，yazi/终端图标字体
  download \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/v${nerd_fonts_version}/NerdFontsSymbolsOnly.tar.xz" \
    "${SCRIPT_DIR}/fonts/NerdFontsSymbolsOnly.tar.xz"
}

target="${1:-all}"
case "$target" in
  macos) download_macos ;;
  linux) download_linux ;;
  all)   download_macos; download_linux ;;
  *)
    error "未知参数: $target（支持 macos / linux / all）"
    exit 1
    ;;
esac

echo -e "\n${GREEN}${BOLD}✓ 下载完成，可将文件 git add 后提交到仓库。${NC}\n"
