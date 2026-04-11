#!/usr/bin/env bash
#
# Yazi 终端文件管理器安装配置脚本
# 支持 macOS (Homebrew) 和 Linux (二进制包/包管理器)
#

set -euo pipefail

info()    { echo -e "\033[34m[INFO]\033[0m $1"; }
success() { echo -e "\033[32m[OK]\033[0m $1"; }
warn()    { echo -e "\033[33m[WARN]\033[0m $1"; }
error()   { echo -e "\033[31m[ERROR]\033[0m $1"; }
step()    { echo -e "\033[36m[STEP]\033[0m $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
YAZI_CONFIG_DIR="$HOME/.config/yazi"
OS="$(uname -s)"
ARCH="$(uname -m)"
DRY_RUN=false

# --- Help ---
show_help() {
    cat <<'EOF'
Yazi 终端文件管理器安装配置脚本

该脚本会执行以下操作:
  1. 安装 Yazi 及其可选依赖
     - macOS 通过 Homebrew 安装
     - Linux 通过二进制包或包管理器安装
  2. 安装可选依赖: ffmpeg, 7zip, jq, poppler, fd, ripgrep, fzf, zoxide
  3. 备份已有的 Yazi 配置 (如果存在)
  4. 复制配置文件到 ~/.config/yazi/
  5. 在 ~/.zshrc 中添加 shell wrapper 函数 (yy)

用法:
  ./setup.sh              运行完整安装
  ./setup.sh --backup     备份现有配置到当前目录
  ./setup.sh --restore    从当前目录恢复配置
  ./setup.sh --dry-run    试运行，只显示将要执行的操作
  ./setup.sh --help       显示此帮助信息

Shell 集成 (安装后):
  yy          启动 yazi，退出时自动切换到浏览的目录
  yazi        直接启动 yazi (不切换目录)

常用快捷键:
  h/j/k/l     导航 (左/下/上/右)
  Enter       进入目录或打开文件
  q           退出并切换目录 (配合 yy 使用)
  Q           退出不切换目录
  y           复制
  d           剪切
  p           粘贴
  r           重命名
  /           搜索
  t           新建标签页
  .           切换隐藏文件显示

EOF
    exit 0
}

# --- Install yazi on macOS ---
install_yazi_macos() {
    if ! command -v brew &>/dev/null; then
        error "Homebrew 未安装，请先安装: https://brew.sh"
        exit 1
    fi

    info "通过 Homebrew 安装 Yazi..."
    brew install yazi

    info "安装可选依赖..."
    local optional_deps=(ffmpeg jq poppler fd ripgrep fzf zoxide)
    for dep in "${optional_deps[@]}"; do
        if brew list "$dep" &>/dev/null 2>/dev/null; then
            success "$dep 已安装"
        else
            brew install "$dep" 2>/dev/null || warn "跳过 $dep (安装失败)"
        fi
    done

    # sevenzip
    if ! brew list sevenzip &>/dev/null 2>/dev/null; then
        brew install sevenzip 2>/dev/null || warn "跳过 sevenzip (安装失败)"
    else
        success "sevenzip 已安装"
    fi
}

# --- Install yazi on Linux ---
install_yazi_linux() {
    # Try package managers first
    if command -v dnf &>/dev/null; then
        install_yazi_fedora
    elif command -v apt-get &>/dev/null; then
        install_yazi_binary
        install_deps_apt
    elif command -v pacman &>/dev/null; then
        install_yazi_arch
    elif command -v yum &>/dev/null; then
        install_yazi_binary
        install_deps_yum
    else
        warn "未识别的包管理器，尝试安装二进制版本..."
        install_yazi_binary
    fi
}

install_yazi_fedora() {
    info "通过 COPR 安装 Yazi (Fedora/CentOS/RHEL)..."

    # Install dnf-plugins-core if needed
    if ! dnf copr list 2>/dev/null | grep -q lihaohong/yazi; then
        if ! rpm -q dnf-plugins-core &>/dev/null; then
            sudo dnf install -y dnf-plugins-core 2>/dev/null || true
        fi
        sudo dnf copr enable -y lihaohong/yazi 2>/dev/null || {
            warn "COPR 启用失败，尝试安装二进制版本..."
            install_yazi_binary
            return
        }
    fi

    sudo dnf install -y yazi || {
        warn "COPR 安装失败，尝试安装二进制版本..."
        install_yazi_binary
        return
    }

    info "安装可选依赖..."
    local deps=(ffmpeg jq fd ripgrep fzf zoxide)
    for dep in "${deps[@]}"; do
        sudo dnf install -y "$dep" 2>/dev/null || warn "跳过 $dep"
    done
    sudo dnf install -y p7zip p7zip-plugins 2>/dev/null || warn "跳过 7zip"
    sudo dnf install -y poppler-utils 2>/dev/null || warn "跳过 poppler"
}

install_yazi_arch() {
    info "通过 pacman 安装 Yazi (Arch Linux)..."
    sudo pacman -S --noconfirm yazi ffmpeg 7zip jq poppler fd ripgrep fzf zoxide
}

install_deps_apt() {
    info "安装可选依赖 (Debian/Ubuntu)..."
    local deps=(ffmpeg jq fd-find ripgrep fzf zoxide poppler-utils)
    for dep in "${deps[@]}"; do
        sudo apt-get install -y "$dep" 2>/dev/null || warn "跳过 $dep"
    done
    sudo apt-get install -y p7zip-full 2>/dev/null || warn "跳过 7zip"

    # fd-find symlink
    if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
        sudo ln -sf /usr/bin/fdfind /usr/local/bin/fd 2>/dev/null || true
    fi
}

install_deps_yum() {
    info "安装可选依赖 (CentOS/RHEL)..."
    local deps=(ffmpeg jq fd ripgrep fzf zoxide)
    for dep in "${deps[@]}"; do
        sudo yum install -y "$dep" 2>/dev/null || warn "跳过 $dep"
    done
    sudo yum install -y p7zip p7zip-plugins 2>/dev/null || warn "跳过 7zip"
}

install_yazi_binary() {
    info "从 GitHub Releases 安装 Yazi 二进制包..."

    # Ensure unzip is available
    if ! command -v unzip &>/dev/null; then
        info "安装 unzip..."
        if command -v dnf &>/dev/null; then
            sudo dnf install -y unzip 2>/dev/null || true
        elif command -v apt-get &>/dev/null; then
            sudo apt-get install -y unzip 2>/dev/null || true
        elif command -v yum &>/dev/null; then
            sudo yum install -y unzip 2>/dev/null || true
        fi
    fi

    local install_dir="$HOME/.local/bin"
    mkdir -p "$install_dir"

    # Determine binary name based on arch
    local binary_arch
    case "$ARCH" in
        x86_64)  binary_arch="x86_64-unknown-linux-musl" ;;
        aarch64) binary_arch="aarch64-unknown-linux-musl" ;;
        *)
            error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac

    local release_url="https://github.com/sxyazi/yazi/releases/latest/download/yazi-${binary_arch}.zip"
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    info "下载 yazi-${binary_arch}.zip..."
    if curl -fLo "$tmp_dir/yazi.zip" "$release_url"; then
        cd "$tmp_dir"
        unzip -q yazi.zip
        local extracted_dir
        extracted_dir="$(find "$tmp_dir" -maxdepth 1 -type d -name "yazi-*" | head -1)"

        if [ -d "$extracted_dir" ]; then
            mv "$extracted_dir/yazi" "$install_dir/yazi"
            mv "$extracted_dir/ya" "$install_dir/ya" 2>/dev/null || true
            chmod +x "$install_dir/yazi" "$install_dir/ya" 2>/dev/null || true
            success "Yazi 安装到 $install_dir"
        else
            error "解压失败，未找到 yazi 目录"
            rm -rf "$tmp_dir"
            exit 1
        fi
    else
        error "下载失败: $release_url"
        rm -rf "$tmp_dir"
        exit 1
    fi

    rm -rf "$tmp_dir"

    # Ensure install_dir is in PATH
    ensure_in_path "$install_dir"
}

ensure_in_path() {
    local dir="$1"
    if [[ ":$PATH:" != *":$dir:"* ]]; then
        info "将 $dir 添加到 PATH..."
        local export_line="export PATH=\"$dir:\$PATH\""
        if [ -f "$HOME/.zshrc" ] && ! grep -qF "$export_line" "$HOME/.zshrc"; then
            echo "$export_line" >> "$HOME/.zshrc"
        fi
        if [ -f "$HOME/.bashrc" ] && ! grep -qF "$export_line" "$HOME/.bashrc"; then
            echo "$export_line" >> "$HOME/.bashrc"
        fi
        export PATH="$dir:$PATH"
    fi
}

# --- Backup existing config ---
backup_config() {
    if [ ! -d "$YAZI_CONFIG_DIR" ]; then
        error "没有找到已有的 Yazi 配置"
        exit 1
    fi

    local backup_dir="$SCRIPT_DIR/backup_$(date +%Y%m%d_%H%M%S)"
    info "备份 Yazi 配置到 $backup_dir..."
    cp -r "$YAZI_CONFIG_DIR" "$backup_dir"
    success "备份完成: $backup_dir"
    exit 0
}

# --- Restore config ---
restore_config() {
    if [ ! -d "$SCRIPT_DIR/config" ]; then
        error "未找到 $SCRIPT_DIR/config 配置目录"
        exit 1
    fi

    if [ -d "$YAZI_CONFIG_DIR" ]; then
        local backup="$YAZI_CONFIG_DIR.bak.$(date +%Y%m%d%H%M%S)"
        info "备份现有配置到 $backup"
        mv "$YAZI_CONFIG_DIR" "$backup"
    fi

    mkdir -p "$YAZI_CONFIG_DIR"
    cp -r "$SCRIPT_DIR/config/." "$YAZI_CONFIG_DIR/"
    success "配置已从 $SCRIPT_DIR/config 恢复"
    exit 0
}

# --- Copy configuration files ---
copy_config() {
    step "复制 Yazi 配置文件..."

    if [ ! -d "$SCRIPT_DIR/config" ]; then
        warn "未找到配置目录 $SCRIPT_DIR/config，跳过配置复制"
        return
    fi

    # Backup existing config
    if [ -d "$YAZI_CONFIG_DIR" ]; then
        local backup="$YAZI_CONFIG_DIR.bak.$(date +%Y%m%d%H%M%S)"
        info "备份现有配置到 $backup"
        mv "$YAZI_CONFIG_DIR" "$backup"
    fi

    mkdir -p "$YAZI_CONFIG_DIR"
    cp -r "$SCRIPT_DIR/config/." "$YAZI_CONFIG_DIR/"
    success "配置已复制到 $YAZI_CONFIG_DIR"
}

# --- Add shell wrapper to zshrc ---
add_shell_wrapper() {
    step "配置 shell wrapper 函数..."

    local zshrc="$HOME/.zshrc"
    local bashrc="$HOME/.bashrc"

    # Shell wrapper that changes directory on exit
    local wrapper='
# Yazi shell wrapper: 退出时自动切换到浏览目录
function yy() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}'

    local marker="# Yazi shell wrapper: 退出时自动切换到浏览目录"

    if [ -f "$zshrc" ]; then
        if grep -qF "$marker" "$zshrc"; then
            success "Shell wrapper 已存在于 ~/.zshrc"
        else
            if [ "$DRY_RUN" = true ]; then
                info "[dry-run] 将向 ~/.zshrc 添加 yy() wrapper 函数"
            else
                echo "$wrapper" >> "$zshrc"
                success "Shell wrapper 已添加到 ~/.zshrc"
            fi
        fi
    fi

    if [ -f "$bashrc" ]; then
        if grep -qF "$marker" "$bashrc"; then
            success "Shell wrapper 已存在于 ~/.bashrc"
        else
            if [ "$DRY_RUN" = true ]; then
                info "[dry-run] 将向 ~/.bashrc 添加 yy() wrapper 函数"
            else
                echo "$wrapper" >> "$bashrc"
                success "Shell wrapper 已添加到 ~/.bashrc"
            fi
        fi
    fi
}

# --- Verify installation ---
verify_install() {
    if command -v yazi &>/dev/null; then
        local version
        version="$(yazi --version 2>&1 | head -1)"
        success "Yazi 安装成功: $version"
    else
        error "Yazi 安装验证失败，请检查 PATH 配置"
        exit 1
    fi
}

# --- Main ---
main() {
    step "开始安装 Yazi..."
    info "检测到系统: $OS ($ARCH)"

    if [ "$DRY_RUN" = true ]; then
        info "试运行模式，不会实际修改系统"
    fi

    # Install yazi
    step "安装 Yazi..."
    if command -v yazi &>/dev/null; then
        success "Yazi 已安装: $(yazi --version 2>&1 | head -1)"
    else
        if [ "$DRY_RUN" = false ]; then
            case "$OS" in
                Darwin) install_yazi_macos ;;
                Linux)  install_yazi_linux ;;
                *)      error "不支持的操作系统: $OS"; exit 1 ;;
            esac
        else
            info "[dry-run] 将安装 Yazi 及其依赖"
        fi
    fi

    # Copy config
    if [ "$DRY_RUN" = false ]; then
        copy_config
    else
        info "[dry-run] 将复制配置文件到 ~/.config/yazi/"
    fi

    # Add shell wrapper
    add_shell_wrapper

    # Verify
    if [ "$DRY_RUN" = false ]; then
        verify_install
    fi

    echo ""
    echo "╔════════════════════════════════════════════════════╗"
    echo "║         Yazi 配置完成! (Setup Complete!)           ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo ""
    success "Yazi 已就绪!"
    echo ""
    echo "快速参考 (Quick Reference):"
    echo "  yy          启动 Yazi (退出时自动切换目录)"
    echo "  yazi        直接启动 Yazi"
    echo ""
    echo "常用快捷键:"
    echo "  h/j/k/l     导航"
    echo "  Enter       进入目录或打开文件"
    echo "  q           退出 (yy 模式下切换目录)"
    echo "  y/d/p       复制/剪切/粘贴"
    echo "  r           重命名"
    echo "  /           搜索"
    echo "  .           切换隐藏文件显示"
    echo "  t           新建标签页"
    echo ""

    if [ "$DRY_RUN" = false ]; then
        echo "  提示: 重新打开终端或运行 'source ~/.zshrc' 以激活 yy 函数"
        echo ""
    fi
}

# --- Parse arguments ---
case "${1:-}" in
    --help|-h)      show_help ;;
    --backup|-b)    backup_config ;;
    --restore|-r)   restore_config ;;
    --dry-run|-d)   DRY_RUN=true; main ;;
    *)              main ;;
esac
