#!/usr/bin/env bash
# 预下载所有离线安装包到 cache 目录
# 用法: ./download.sh [macos|linux|all]  （默认 all）
#
# Linux 二进制版本优先从 os/linux/packages.centos.list 读取，避免双处维护。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
BINARIES_DIR="${SCRIPT_DIR}/binaries"
FONTS_DIR="${SCRIPT_DIR}/fonts"
PACKAGES_CENTOS_LIST="${SCRIPT_DIR}/../os/linux/packages.centos.list"

# shellcheck source=../os/lib/packages_list.sh
source "${SCRIPT_DIR}/../os/lib/packages_list.sh"

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

# Portable SHA-256 (GNU sha256sum or macOS shasum).
file_sha256() {
  local file="$1" bin
  for bin in sha256sum /usr/bin/sha256sum /bin/sha256sum; do
    if command -v "$bin" >/dev/null 2>&1 || [[ -x "$bin" ]]; then
      "$bin" "$file" | awk '{print $1}'
      return 0
    fi
  done
  for bin in shasum /usr/bin/shasum; do
    if command -v "$bin" >/dev/null 2>&1 || [[ -x "$bin" ]]; then
      "$bin" -a 256 "$file" | awk '{print $1}'
      return 0
    fi
  done
  return 1
}

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

# 下载固定校验和的文件；仅在校验成功后原子替换目标文件。
download_verified() {
  local url="$1"
  local dest="$2"
  local expected_sha256="$3"
  local actual_sha256 tmp

  if [[ -f "$dest" ]]; then
    actual_sha256="$(file_sha256 "$dest")" || actual_sha256=""
    if [[ "$actual_sha256" == "$expected_sha256" ]]; then
      info "已存在且校验通过，跳过: $(basename "$dest")"
      return 0
    fi
    warn "校验失败，删除后重新下载: $(basename "$dest")"
    rm -f "$dest"
  fi

  tmp="$(mktemp "${dest}.tmp.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  trap 'exit 130' HUP INT TERM
  info "下载并校验: $(basename "$dest") ..."
  if ! curl -fsSL "$url" -o "$tmp"; then
    error "失败: $url"
    rm -f "$tmp"
    trap - EXIT HUP INT TERM
    return 1
  fi

  actual_sha256="$(file_sha256 "$tmp")" || actual_sha256=""
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    error "SHA-256 校验失败: $(basename "$dest")"
    rm -f "$tmp"
    trap - EXIT HUP INT TERM
    return 1
  fi

  mv "$tmp" "$dest"
  trap - EXIT HUP INT TERM
  success "完成并校验: $(basename "$dest")"
}

download_git_delta() {
  local version="0.19.2"
  local target="x86_64-unknown-linux-musl"
  local filename="delta-${version}-${target}.tar.gz"
  local sha256="f1ea01ca7728ce3462debc359f39dfc7cbbc1a63224b71fefabf92042864aa1b"
  download_verified \
    "https://github.com/dandavison/delta/releases/download/${version}/${filename}" \
    "${BINARIES_DIR}/${filename}" \
    "$sha256"
}

# Alinux 3 E2E: kernel-headers is only in the heavy plus repo. Pin the RPM so
# the image build does not download plus metadata.
download_alinux3_kernel_headers() {
  local filename="kernel-headers-5.10.134-20.2.al8.x86_64.rpm"
  local sha256="18bea523d468e822a24a74e2427e62355b278895f76516941db1c1a3d890893a"
  download_verified \
    "https://mirrors.aliyun.com/alinux/3/plus/x86_64/kernels/${filename}" \
    "${BINARIES_DIR}/${filename}" \
    "$sha256"
}

# VPN 客户端 geoip/geosite（Loyalsoldier；架构无关，linux/macos 共用）
download_vpn_geodata() {
  download \
    "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" \
    "${BINARIES_DIR}/geoip.dat"
  download \
    "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" \
    "${BINARIES_DIR}/geosite.dat"
}

pkg_version() {
  local name="$1" fallback="$2"
  local ver
  if [[ -f "$PACKAGES_CENTOS_LIST" ]] && ver="$(packages_list_get_version "$PACKAGES_CENTOS_LIST" "$name" 2>/dev/null)"; then
    echo "$ver"
  else
    warn "无法从 packages.centos.list 读取 ${name}，使用回退版本 ${fallback}"
    echo "$fallback"
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

  # VPN macOS 客户端同样需要 geo 路由数据
  download_vpn_geodata
}

download_linux() {
  echo -e "\n${BOLD}▶ Linux 所需文件${NC}"

  # git-delta（CentOS 7 x86_64 离线兼容）
  download_git_delta

  # Alinux 3 E2E 编译依赖（避免拉取 plus 仓库元数据）
  download_alinux3_kernel_headers

  # 安装脚本
  download \
    "https://download.docker.com/linux/centos/docker-ce.repo" \
    "${SCRIPTS_DIR}/docker-ce.repo"
  local node_version
  node_version="$(pkg_version node 20)"
  download \
    "https://rpm.nodesource.com/setup_${node_version}.x" \
    "${SCRIPTS_DIR}/nodesource-setup-${node_version}.x"
  download \
    "https://github.com/XTLS/Xray-install/raw/main/install-release.sh" \
    "${SCRIPTS_DIR}/install-release.sh"

  # 二进制包版本（来自 packages.centos.list；未列出的保持本地默认）
  local yazi_version lazygit_version glow_version fzf_version zoxide_version nerd_fonts_version tmux_version
  local bat_version rg_version
  yazi_version="$(pkg_version yazi 0.3.3)"
  lazygit_version="$(pkg_version lazygit 0.44.1)"
  glow_version="$(pkg_version glow 2.1.2)"
  fzf_version="$(pkg_version fzf 0.72.0)"
  zoxide_version="$(pkg_version zoxide 0.9.4)"
  nerd_fonts_version="$(pkg_version nerd-fonts 3.3.0)"
  tmux_version="$(pkg_version tmux 3.7b)"
  bat_version="$(pkg_version bat 0.25.0)"
  rg_version="$(pkg_version rg 14.1.1)"
  local starship_version="1.25.1"
  local xray_version="26.3.27"

  info "版本: yazi=${yazi_version} lazygit=${lazygit_version} glow=${glow_version} fzf=${fzf_version} zoxide=${zoxide_version} bat=${bat_version} rg=${rg_version} nerd-fonts=${nerd_fonts_version} tmux=${tmux_version}"

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

  # glow (x86_64 / arm64)
  for arch in x86_64 arm64; do
    download \
      "https://github.com/charmbracelet/glow/releases/download/v${glow_version}/glow_${glow_version}_Linux_${arch}.tar.gz" \
      "${BINARIES_DIR}/glow_${glow_version}_Linux_${arch}.tar.gz"
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

  # bat (x86_64 / arm64)
  for arch in x86_64-unknown-linux-musl aarch64-unknown-linux-musl; do
    download \
      "https://github.com/sharkdp/bat/releases/download/v${bat_version}/bat-v${bat_version}-${arch}.tar.gz" \
      "${BINARIES_DIR}/bat-v${bat_version}-${arch}.tar.gz"
  done

  # ripgrep / rg (x86_64 / arm64)
  for arch in x86_64-unknown-linux-musl aarch64-unknown-linux-musl; do
    download \
      "https://github.com/BurntSushi/ripgrep/releases/download/${rg_version}/ripgrep-${rg_version}-${arch}.tar.gz" \
      "${BINARIES_DIR}/ripgrep-${rg_version}-${arch}.tar.gz"
  done

  # Starship (x86_64 / arm64) — musl 静态编译版，适合兼容性较差的 ECS 系统
  for arch in x86_64-unknown-linux-musl aarch64-unknown-linux-musl; do
    download \
      "https://github.com/starship/starship/releases/download/v${starship_version}/starship-${arch}.tar.gz" \
      "${BINARIES_DIR}/starship-${arch}.tar.gz"
  done

  # Xray-core（network/vpn/client/linux_setup.sh）
  for arch in 64 arm64-v8a arm32-v7a; do
    download \
      "https://github.com/XTLS/Xray-core/releases/download/v${xray_version}/Xray-linux-${arch}.zip" \
      "${BINARIES_DIR}/Xray-linux-${arch}-v${xray_version}.zip"
  done

  # Loyalsoldier geo 路由数据（VPN 客户端国内分流；jsdelivr 在国内易超时）
  download_vpn_geodata

  # tmux 源码包（terminal/tmux/setup.sh / os/linux 源码编译用）
  download \
    "https://github.com/tmux/tmux/releases/download/${tmux_version}/tmux-${tmux_version}.tar.gz" \
    "${BINARIES_DIR}/tmux-${tmux_version}.tar.gz"

  # Neovim tarball（editors/nvim/setup.sh）— 固定 v0.10.4；不用 AppImage（需 FUSE）
  local nvim_version="0.10.4"
  for arch in linux-x86_64 linux-arm64; do
    download \
      "https://github.com/neovim/neovim/releases/download/v${nvim_version}/nvim-${arch}.tar.gz" \
      "${BINARIES_DIR}/nvim-${arch}-v${nvim_version}.tar.gz"
  done

  # Nerd Fonts Symbols Only — 架构无关，yazi/终端图标字体
  download \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/v${nerd_fonts_version}/NerdFontsSymbolsOnly.tar.xz" \
    "${FONTS_DIR}/NerdFontsSymbolsOnly.tar.xz"
}

main() {
  local target="${1:-all}"
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
}

if [[ "${CACHE_DOWNLOAD_NO_MAIN:-false}" != "true" && "${CACHE_DOWNLOAD_NO_MAIN:-false}" != "1" ]]; then
  main "$@"
fi
