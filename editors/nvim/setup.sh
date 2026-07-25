#!/bin/bash
# ============================================================
# Neovim Setup Script
# Installs Neovim and configures with lazy.nvim plugins
# ============================================================

set -e

info()    { echo -e "\033[34m[INFO]\033[0m $1"; }
success() { echo -e "\033[32m[OK]\033[0m $1"; }
warn()    { echo -e "\033[33m[WARN]\033[0m $1"; }
error()   { echo -e "\033[31m[ERROR]\033[0m $1"; }
step()    { echo -e "\033[36m[STEP]\033[0m $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NVIM_CONFIG_DIR="$HOME/.config/nvim"

# --- Help ---
show_help() {
    cat <<'EOF'
Neovim Setup Script - 一键配置 Neovim 开发环境

该脚本会执行以下配置:
  1. 安装/更新 Neovim (0.9.0+)
     - macOS 通过 Homebrew 安装
     - Linux 通过官方 AppImage 或包管理器安装
  2. 安装依赖: node, npm, ripgrep, fd, git
  3. 备份已有的 Neovim 配置 (如果存在)
  4. 安装 lazy.nvim 插件管理器
  5. 配置 init.lua 和 lua/ 目录
  6. 自动安装所有插件和 LSP 语言服务器
  7. 安装 Nerd Font 字体 (用于图标显示)

用法:
  ./setup.sh              运行完整安装
  ./setup.sh --backup     备份现有配置到当前目录
  ./setup.sh --restore    从当前目录恢复配置
  ./setup.sh --update     仅更新插件
  ./setup.sh --help       显示此帮助信息

快捷键速查 (Leader 键为空格 <Space>):
  <Space>e     切换文件树 (nvim-tree)
  <Space>ff    模糊查找文件 (Telescope)
  <Space>fg    全局搜索 (Telescope live_grep)
  <Space>fb    列出缓冲区 (Telescope buffers)
  gd           跳转到定义
  gr           查找引用
  K            显示文档
  <Space>rn    重命名符号
  <Space>ca    代码操作
  <Space>gs    Git status
  <Space>gb    Git blame
  <Space>gd    Git diff
  <Space>gg    打开 LazyGit
EOF
    exit 0
}

# --- Detect OS ---
OS="$(uname -s)"
ARCH="$(uname -m)"

# --- Check if Neovim is installed ---
get_nvim_version() {
    if command -v nvim &>/dev/null; then
        nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
    else
        echo ""
    fi
}

version_compare() {
    local v1="$1"
    local v2="$2"

    if [ -z "$v1" ]; then
        echo "lt"
        return
    fi

    local IFS=.
    local i ver1=($v1) ver2=($v2)

    for ((i=0; i<${#ver1[@]} || i<${#ver2[@]}; i++)); do
        local x=${ver1[i]:-0}
        local y=${ver2[i]:-0}
        if ((x < y)); then
            echo "lt"
            return
        elif ((x > y)); then
            echo "gt"
            return
        fi
    done
    echo "eq"
}

# --- Install Neovim ---
install_nvim_macos() {
    if ! command -v brew &>/dev/null; then
        error "Homebrew not found. Install it first: https://brew.sh"
        exit 1
    fi

    if brew list neovim &>/dev/null; then
        info "Updating Neovim via Homebrew..."
        brew upgrade neovim 2>/dev/null || success "Neovim already up to date"
    else
        info "Installing Neovim via Homebrew..."
        brew install neovim
    fi
    success "Neovim installed"
}

install_nvim_linux() {
    local current_version
    current_version=$(get_nvim_version)

    if [ "$(version_compare "$current_version" "0.9.0")" = "lt" ]; then
        info "Installing Neovim via AppImage..."

        # Download latest stable AppImage
        local nvim_url="https://github.com/neovim/neovim/releases/download/stable/nvim.appimage"
        local nvim_path="$HOME/.local/bin/nvim"

        mkdir -p "$HOME/.local/bin"

        if curl -fLo /tmp/nvim.appimage "$nvim_url" 2>/dev/null; then
            chmod +x /tmp/nvim.appimage
            mv /tmp/nvim.appimage "$nvim_path"
            success "Neovim AppImage installed to $nvim_path"

            # Add to PATH if needed
            if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc" 2>/dev/null || true
                export PATH="$HOME/.local/bin:$PATH"
            fi
        else
            warn "Failed to download AppImage, trying package manager..."
            install_nvim_linux_package_manager
        fi
    else
        success "Neovim $current_version already installed"
    fi
}

install_nvim_linux_package_manager() {
    if command -v apt-get &>/dev/null; then
        info "Installing Neovim via apt..."
        sudo apt-get update
        sudo apt-get install -y neovim
    elif command -v yum &>/dev/null; then
        info "Installing Neovim via yum..."
        sudo yum install -y neovim
    elif command -v dnf &>/dev/null; then
        info "Installing Neovim via dnf..."
        sudo dnf install -y neovim
    elif command -v pacman &>/dev/null; then
        info "Installing Neovim via pacman..."
        sudo pacman -S --noconfirm neovim
    else
        error "Unsupported package manager. Install Neovim manually: https://github.com/neovim/neovim/wiki/Installing-Neovim"
        exit 1
    fi
    success "Neovim installed"
}

install_nvim() {
    step "Installing Neovim..."
    case "$OS" in
        Darwin) install_nvim_macos ;;
        Linux)  install_nvim_linux ;;
        *)      error "Unsupported OS: $OS"; exit 1 ;;
    esac

    # Verify installation
    local version
    version=$(get_nvim_version)
    if [ -z "$version" ]; then
        error "Neovim installation failed"
        exit 1
    fi
    success "Neovim version: $version"
}

# --- Install dependencies ---
install_deps_macos() {
    info "Installing dependencies via Homebrew..."
    local deps=(node npm ripgrep fd git)
    for dep in "${deps[@]}"; do
        if brew list "$dep" &>/dev/null 2>/dev/null; then
            success "$dep already installed"
        else
            info "Installing $dep..."
            brew install "$dep" || warn "Failed to install $dep"
        fi
    done
}

install_deps_linux() {
    info "Installing dependencies..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update
        # Install packages individually to avoid failure on missing packages
        for pkg in nodejs npm ripgrep git curl; do
            sudo apt-get install -y "$pkg" 2>/dev/null || warn "Failed to install $pkg"
        done
        # fd-find may not be available on all systems, try fd or fd-find
        if sudo apt-get install -y fd-find 2>/dev/null; then
            # Create fd symlink if needed
            if ! command -v fd &>/dev/null && command -v fdfind &>/dev/null; then
                sudo ln -sf /usr/bin/fdfind /usr/bin/fd
            fi
        else
            warn "fd-find not available, skipping"
        fi
    elif command -v yum &>/dev/null; then
        for pkg in nodejs npm ripgrep git curl; do
            sudo yum install -y "$pkg" 2>/dev/null || warn "Failed to install $pkg"
        done
        sudo yum install -y fd 2>/dev/null || warn "Failed to install fd"
    elif command -v dnf &>/dev/null; then
        for pkg in nodejs npm ripgrep git curl; do
            sudo dnf install -y "$pkg" 2>/dev/null || warn "Failed to install $pkg"
        done
        sudo dnf install -y fd-find 2>/dev/null || warn "Failed to install fd-find"
    elif command -v pacman &>/dev/null; then
        for pkg in nodejs npm ripgrep git curl; do
            sudo pacman -S --noconfirm "$pkg" 2>/dev/null || warn "Failed to install $pkg"
        done
        sudo pacman -S --noconfirm fd 2>/dev/null || warn "Failed to install fd"
    else
        warn "Could not install dependencies automatically"
    fi
}

install_deps() {
    step "Installing dependencies..."
    case "$OS" in
        Darwin) install_deps_macos ;;
        Linux)  install_deps_linux ;;
    esac
}

# --- Backup existing config ---
backup_config() {
    if [ ! -d "$NVIM_CONFIG_DIR" ]; then
        error "No existing Neovim config to backup"
        exit 1
    fi

    local backup_dir="$SCRIPT_DIR/backup_$(date +%Y%m%d_%H%M%S)"
    info "Backing up Neovim config to $backup_dir..."
    cp -r "$NVIM_CONFIG_DIR" "$backup_dir"
    success "Backup complete: $backup_dir"
    exit 0
}

# --- Restore config ---
restore_config() {
    if [ ! -f "$SCRIPT_DIR/init.lua" ]; then
        error "init.lua not found in $SCRIPT_DIR"
        exit 1
    fi

    # Backup existing config
    if [ -d "$NVIM_CONFIG_DIR" ]; then
        local backup="$NVIM_CONFIG_DIR.bak.$(date +%Y%m%d%H%M%S)"
        info "Backing up existing config to $backup"
        mv "$NVIM_CONFIG_DIR" "$backup"
    fi

    # Create config directory
    mkdir -p "$NVIM_CONFIG_DIR"

    # Copy config files
    cp -r "$SCRIPT_DIR/init.lua" "$NVIM_CONFIG_DIR/"
    if [ -d "$SCRIPT_DIR/lua" ]; then
        cp -r "$SCRIPT_DIR/lua" "$NVIM_CONFIG_DIR/"
    fi

    success "Config restored from $SCRIPT_DIR"

    # Install plugins
    info "Installing plugins..."
    nvim --headless +Lazy! sync +qall 2>/dev/null || true
    success "Plugins installed"

    # Install LSPs
    info "Installing LSP servers..."
    nvim --headless +MasonToolsInstallSync +qall 2>/dev/null || true
    success "LSP servers installed"

    exit 0
}

# --- Update plugins ---
update_plugins() {
    if ! command -v nvim &>/dev/null; then
        error "Neovim not found"
        exit 1
    fi

    step "Updating plugins..."
    nvim --headless +Lazy! sync +qall 2>/dev/null || true
    success "Plugins updated"

    step "Updating LSP servers..."
    nvim --headless +MasonToolsUpdateSync +qall 2>/dev/null || true
    success "LSP servers updated"
}

# --- Install Nerd Font ---
install_nerd_font() {
    step "Installing Nerd Font..."

    case "$OS" in
        Darwin)
            if ! command -v brew &>/dev/null; then
                warn "Homebrew not found, skipping font installation"
                return
            fi

            local font_name="font-meslo-lg-nerd-font"
            if brew list --cask "$font_name" &>/dev/null; then
                success "Font $font_name already installed"
            else
                info "Installing $font_name via Homebrew..."
                brew install --cask "$font_name"
                success "Font installed"
            fi
            ;;

        Linux)
            local font_dir="$HOME/.local/share/fonts"

            if fc-list 2>/dev/null | grep -qi "MesloLGS NF"; then
                success "MesloLGS NF font already installed"
                return
            fi

            info "Installing MesloLGS Nerd Font..."
            mkdir -p "$font_dir"

            local fonts=(
                "MesloLGS%20NF%20Regular.ttf"
                "MesloLGS%20NF%20Bold.ttf"
                "MesloLGS%20NF%20Italic.ttf"
                "MesloLGS%20NF%20Bold%20Italic.ttf"
            )
            local base_url="https://github.com/romkatv/powerlevel10k-media/raw/master"

            for font in "${fonts[@]}"; do
                local font_name=$(echo "$font" | sed 's/%20/ /g')
                local target="$font_dir/$font_name"

                if [ -f "$target" ]; then
                    success "$font_name already exists"
                else
                    info "Downloading $font_name..."
                    curl -fLo "$target" "$base_url/$font" 2>/dev/null || warn "Failed to download $font_name"
                fi
            done

            fc-cache -f "$font_dir" 2>/dev/null || true
            success "Font installed"
            ;;
    esac

    echo ""
    echo -e "\033[33m[重要提示]\033[0m 请在终端设置中将字体更改为 'MesloLGS NF' 以正确显示图标"
    echo ""
}

# --- Copy configuration ---
copy_config() {
    step "Copying Neovim configuration..."

    # Backup existing config
    if [ -d "$NVIM_CONFIG_DIR" ] && [ ! -L "$NVIM_CONFIG_DIR" ]; then
        local backup="$NVIM_CONFIG_DIR.bak.$(date +%Y%m%d%H%M%S)"
        info "Backing up existing config to $backup"
        mv "$NVIM_CONFIG_DIR" "$backup"
    fi

    # Remove existing config if it's a symlink
    if [ -L "$NVIM_CONFIG_DIR" ]; then
        rm "$NVIM_CONFIG_DIR"
    fi

    # Create config directory
    mkdir -p "$NVIM_CONFIG_DIR"

    # Copy files
    cp -r "$SCRIPT_DIR/init.lua" "$NVIM_CONFIG_DIR/"
    if [ -d "$SCRIPT_DIR/lua" ]; then
        cp -r "$SCRIPT_DIR/lua" "$NVIM_CONFIG_DIR/"
    fi

    success "Configuration copied to $NVIM_CONFIG_DIR"
}

# --- Main setup ---
main() {
    step "Starting Neovim setup..."
    info "Detected OS: $OS ($ARCH)"

    # Install Neovim if needed
    local current_version
    current_version=$(get_nvim_version)

    if [ -z "$current_version" ] || [ "$(version_compare "$current_version" "0.9.0")" = "lt" ]; then
        install_nvim
    else
        success "Neovim $current_version already installed"
    fi

    # Install dependencies
    install_deps

    # Copy configuration
    copy_config

    # Install Nerd Font
    install_nerd_font

    # First run to install plugins
    step "Installing plugins (this may take a few minutes)..."
    nvim --headless +Lazy! sync +qall 2>/dev/null || true
    success "Plugins installed"

    step "Installing LSP servers..."
    nvim --headless +MasonToolsInstallSync +qall 2>/dev/null || true
    success "LSP servers installed"

    # Done
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         Neovim 配置完成!  (Setup Complete!)                ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    success "Neovim is ready to use!"
    echo ""
    echo "快速参考 (Quick Reference):"
    echo "  <Space>e     切换文件树 (nvim-tree)"
    echo "  <Space>ff    模糊查找文件 (Telescope)"
    echo "  <Space>fg    全局搜索 (Telescope live_grep)"
    echo "  <Space>fb    列出缓冲区 (Telescope buffers)"
    echo "  gd           跳转到定义 (Go to definition)"
    echo "  gr           查找引用 (Find references)"
    echo "  K            显示文档 (Show documentation)"
    echo "  <Space>rn    重命名符号 (Rename symbol)"
    echo "  <Space>ca    代码操作 (Code action)"
    echo "  <Space>gg    打开 LazyGit"
    echo ""
    echo "  启动命令: nvim"
    echo ""
    echo "  提示: 将终端字体设置为 'MesloLGS NF' 以显示图标"
    echo ""
}

# --- Parse arguments ---
case "${1:-}" in
    --help|-h)      show_help ;;
    --backup|-b)    backup_config ;;
    --restore|-r)   restore_config ;;
    --update|-u)    update_plugins ;;
    *)              main ;;
esac
