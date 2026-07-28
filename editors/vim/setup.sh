#!/bin/bash
# ============================================================
# Vim Setup Script
# Installs vimrc, vim-plug, and required system dependencies
# ============================================================

set -e

info()    { echo -e "\033[34m[INFO]\033[0m $1"; }
success() { echo -e "\033[32m[OK]\033[0m $1"; }
warn()    { echo -e "\033[33m[WARN]\033[0m $1"; }
error()   { echo -e "\033[31m[ERROR]\033[0m $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Help ---
show_help() {
    cat <<'EOF'
Vim Setup Script - 一键配置 Vim 开发环境

该脚本会执行以下配置:
  1. 安装系统依赖 (vim, node, ctags, fzf, ripgrep)
     - macOS 通过 Homebrew 安装
     - Linux 通过 apt-get / dnf / yum 安装；fzf、ripgrep 在仓库缺失时
       自动回退到 GitHub 二进制（优先 cache/，安装到 ~/.local/bin）
  2. 检测 Vim 版本 (coc.nvim 需要 Vim 8.1.1719+)
  3. 备份已有的 ~/.vimrc (如果存在)
  4. 将本目录的 vimrc 复制到 ~/.vimrc（覆盖）
  5. 创建 Vim 缓存目录 (~/.vim/gutentags)
  6. 安装 vim-plug 插件管理器并安装所有插件
  7. 安装 Nerd Font 字体 (用于 NERDTree 等插件显示图标)
  8. 安装 coc.nvim 语言服务器 (Python, Go, Java, Shell, JSON, YAML)
     - 如果 Vim 版本过低则跳过此步骤

用法:
  ./setup.sh              运行完整安装
  ./setup.sh --backup     将 ~/.vimrc 备份到当前目录的 vimrc
  ./setup.sh --restore    将当前目录的 vimrc 覆盖到 ~/.vimrc 并安装插件
  ./setup.sh --help       显示此帮助信息

快捷键速查 (Leader 键为逗号 ,):
  ,n         切换文件树 (NERDTree)
  ,t         切换标签侧栏 (Tagbar)
  ,p         模糊查找文件 (FZF)
  ,g         全局搜索 (Ripgrep)
  gd         跳转到定义
  gr         查找引用
  K          显示文档
  ,gs        Git status
  ,gb        Git blame
  ,gd        Git diff
  Tab        接受 Copilot AI 建议（优先）或 coc 补全列表
  Ctrl+]     接受 Copilot 建议中的下一个单词
  Ctrl+E     关闭 Copilot 建议
  Alt+]/[    切换 Copilot 候选建议

AI 补全初始化（首次使用）:
  :Copilot setup    登录 GitHub Copilot（需要订阅）
  如需免费方案，在 vimrc 中切换到 Codeium 插件后运行 :Codeium Auth
EOF
    exit 0
}

# --- Backup ~/.vimrc to current directory ---
backup_vimrc() {
    if [ ! -f "$HOME/.vimrc" ]; then
        error "~/.vimrc does not exist, nothing to backup"
        exit 1
    fi

    info "Backing up ~/.vimrc to $SCRIPT_DIR/vimrc..."
    cp "$HOME/.vimrc" "$SCRIPT_DIR/vimrc"
    success "Backup complete: $SCRIPT_DIR/vimrc"
    exit 0
}

# --- Restore vimrc from current directory and install plugins ---
restore_vimrc() {
    if [ ! -f "$SCRIPT_DIR/vimrc" ]; then
        error "vimrc not found in $SCRIPT_DIR"
        exit 1
    fi

    # Backup regular file; remove symlink first so cp does not write through
    if [ -L "$HOME/.vimrc" ]; then
        info "Removing existing symlink ~/.vimrc"
        rm -f "$HOME/.vimrc"
    elif [ -f "$HOME/.vimrc" ]; then
        BACKUP="$HOME/.vimrc.bak.$(date +%Y%m%d%H%M%S)"
        info "Backing up existing ~/.vimrc to $BACKUP"
        cp "$HOME/.vimrc" "$BACKUP"
    fi

    info "Restoring vimrc from $SCRIPT_DIR/vimrc..."
    cp "$SCRIPT_DIR/vimrc" "$HOME/.vimrc"
    success "vimrc restored to ~/.vimrc"

    # Create cache directories
    mkdir -p "$HOME/.vim/gutentags"

    # Install vim-plug if not exists
    if [ ! -f "$HOME/.vim/autoload/plug.vim" ]; then
        info "Installing vim-plug..."
        curl -fLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
            https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
        success "vim-plug installed"
    fi

    # Install plugins
    info "Installing Vim plugins (this may take a moment)..."
    vim +PlugInstall +qall 2>/dev/null || true
    success "Vim plugins installed"

    # Install coc.nvim language servers via npm (non-interactive)
    info "Installing coc.nvim language servers..."
    EXTENSIONS=(
        "coc-pyright"
        "coc-go"
        "coc-java"
        "coc-sh"
        "coc-json"
        "coc-yaml"
    )

    install_coc_extensions "${EXTENSIONS[@]}"

    # Install Nerd Font
    install_nerd_font

    echo ""
    success "Vim restore complete!"
    exit 0
}

case "${1:-}" in
    --help|-h)     show_help ;;
    --backup|-b)   backup_vimrc ;;
    --restore|-r)  restore_vimrc ;;
esac

# --- Install coc.nvim extensions ---
install_coc_extensions() {
    local extensions=("$@")
    local ext_dir="$HOME/.config/coc/extensions"

    mkdir -p "$ext_dir"

    # Create package.json if missing (required for npm to manage deps correctly)
    if [ ! -f "$ext_dir/package.json" ]; then
        echo '{"dependencies":{}}' > "$ext_dir/package.json"
    fi

    cd "$ext_dir"

    for ext in "${extensions[@]}"; do
        if [ -d "node_modules/$ext" ]; then
            success "$ext already installed"
        else
            info "Installing $ext..."
            # Do NOT use --ignore-scripts or --no-bin-links: LSP binaries need post-install scripts
            npm install "$ext" --global-style --no-package-lock 2>&1 | grep -v "npm WARN" \
                || warn "Failed to install $ext (install manually inside Vim: :CocInstall $ext)"
        fi
    done
    success "Language servers configured"
}

# --- Detect OS ---
OS="$(uname -s)"

install_deps_macos() {
    info "Installing dependencies via Homebrew..."
    if ! command -v brew &>/dev/null; then
        error "Homebrew not found. Install it first: https://brew.sh"
        exit 1
    fi

    local deps=(vim node ctags fzf ripgrep)
    for dep in "${deps[@]}"; do
        if brew list "$dep" &>/dev/null; then
            success "$dep already installed"
        else
            info "Installing $dep..."
            brew install "$dep"
        fi
    done
}

# Install a package via the detected Linux package manager; return non-zero on miss.
_linux_pkg_install() {
    local pkg="$1"
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y "$pkg"
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y "$pkg"
    elif command -v yum &>/dev/null; then
        sudo yum install -y "$pkg"
    else
        return 1
    fi
}

_ensure_local_bin() {
    mkdir -p "$HOME/.local/bin"
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac
}

# fzf is often missing from RHEL/Alinux repos; fall back to GitHub release / git clone.
_install_fzf_linux() {
    if command -v fzf &>/dev/null; then
        success "fzf already installed: $(command -v fzf)"
        return 0
    fi

    info "Installing fzf..."
    if _linux_pkg_install fzf >/dev/null 2>&1 && command -v fzf &>/dev/null; then
        success "fzf installed via package manager"
        return 0
    fi

    local fzf_version="0.72.0"
    local fzf_arch
    case "$(uname -m)" in
        aarch64|arm64) fzf_arch="linux_arm64" ;;
        *)             fzf_arch="linux_amd64" ;;
    esac
    local fzf_filename="fzf-${fzf_version}-${fzf_arch}.tar.gz"
    local cache_dir="${DEVTOOLS_CACHE_DIR:-$SCRIPT_DIR/../../cache}"
    local cached="${cache_dir}/binaries/${fzf_filename}"
    local url="https://github.com/junegunn/fzf/releases/download/v${fzf_version}/${fzf_filename}"
    local tmpdir
    tmpdir="$(mktemp -d)"

    if [[ -f "$cached" ]]; then
        info "Using local cache: binaries/${fzf_filename}"
        cp "$cached" "$tmpdir/fzf.tar.gz"
    elif curl -fL --retry 3 -o "$tmpdir/fzf.tar.gz" "$url"; then
        :
    else
        warn "fzf binary download failed; trying git clone fallback"
        rm -rf "$tmpdir"
        local fzf_dir="$HOME/.fzf"
        if [[ ! -f "$fzf_dir/install" ]]; then
            if [[ -d "$fzf_dir" ]]; then
                mv "$fzf_dir" "${fzf_dir}.backup.$(date +%Y%m%d%H%M%S)"
            fi
            git clone --depth 1 https://github.com/junegunn/fzf.git "$fzf_dir"
        fi
        "$fzf_dir/install" --bin
        if command -v fzf &>/dev/null || [[ -x "$fzf_dir/bin/fzf" ]]; then
            _ensure_local_bin
            if [[ -x "$fzf_dir/bin/fzf" && ! -x "$HOME/.local/bin/fzf" ]]; then
                ln -sf "$fzf_dir/bin/fzf" "$HOME/.local/bin/fzf"
            fi
            success "fzf installed via git clone"
            return 0
        fi
        warn "fzf install failed; FZF features (,p /,g) need a manual install"
        return 1
    fi

    if tar -xzf "$tmpdir/fzf.tar.gz" -C "$tmpdir" fzf 2>/dev/null; then
        _ensure_local_bin
        install -m 755 "$tmpdir/fzf" "$HOME/.local/bin/fzf"
        success "fzf installed to ~/.local/bin/fzf"
        rm -rf "$tmpdir"
        return 0
    fi

    rm -rf "$tmpdir"
    warn "fzf install failed; FZF features (,p /,g) need a manual install"
    return 1
}

# ripgrep (rg) is often missing from RHEL/Alinux repos; fall back to GitHub release.
_install_ripgrep_linux() {
    if command -v rg &>/dev/null; then
        success "ripgrep already installed: $(command -v rg)"
        return 0
    fi

    info "Installing ripgrep..."
    if _linux_pkg_install ripgrep >/dev/null 2>&1 && command -v rg &>/dev/null; then
        success "ripgrep installed via package manager"
        return 0
    fi

    local rg_version="14.1.1"
    local rg_arch
    case "$(uname -m)" in
        aarch64|arm64) rg_arch="aarch64-unknown-linux-musl" ;;
        *)             rg_arch="x86_64-unknown-linux-musl" ;;
    esac
    local rg_dirname="ripgrep-${rg_version}-${rg_arch}"
    local rg_filename="${rg_dirname}.tar.gz"
    local cache_dir="${DEVTOOLS_CACHE_DIR:-$SCRIPT_DIR/../../cache}"
    local cached="${cache_dir}/binaries/${rg_filename}"
    local url="https://github.com/BurntSushi/ripgrep/releases/download/${rg_version}/${rg_filename}"
    local tmpdir
    tmpdir="$(mktemp -d)"

    if [[ -f "$cached" ]]; then
        info "Using local cache: binaries/${rg_filename}"
        cp "$cached" "$tmpdir/rg.tar.gz"
    elif ! curl -fL --retry 3 -o "$tmpdir/rg.tar.gz" "$url"; then
        rm -rf "$tmpdir"
        warn "ripgrep download failed; install manually: https://github.com/BurntSushi/ripgrep/releases"
        return 1
    fi

    if tar -xzf "$tmpdir/rg.tar.gz" -C "$tmpdir" 2>/dev/null && [[ -x "$tmpdir/$rg_dirname/rg" ]]; then
        _ensure_local_bin
        install -m 755 "$tmpdir/$rg_dirname/rg" "$HOME/.local/bin/rg"
        success "ripgrep installed to ~/.local/bin/rg"
        rm -rf "$tmpdir"
        return 0
    fi

    rm -rf "$tmpdir"
    warn "ripgrep install failed; install manually: https://github.com/BurntSushi/ripgrep/releases"
    return 1
}

install_deps_linux() {
    info "Installing dependencies via package manager..."

    if command -v apt-get &>/dev/null; then
        sudo apt-get update
    elif ! command -v dnf &>/dev/null && ! command -v yum &>/dev/null; then
        error "Unsupported package manager. Install manually: vim, nodejs, npm, ctags, fzf, ripgrep"
        exit 1
    fi

    # Install packages individually so missing names (common on Alinux/RHEL) do not abort.
    local pkg
    if command -v apt-get &>/dev/null; then
        for pkg in vim nodejs npm universal-ctags curl git; do
            if _linux_pkg_install "$pkg" 2>/dev/null; then
                success "$pkg installed/present"
            else
                warn "Failed to install $pkg via apt-get"
            fi
        done
    else
        for pkg in vim-enhanced vim nodejs npm ctags curl git; do
            # vim-enhanced provides /usr/bin/vim on RHEL-family; plain "vim" may be absent.
            if [[ "$pkg" == "vim" ]] && command -v vim &>/dev/null; then
                success "vim already installed"
                continue
            fi
            if [[ "$pkg" == "vim-enhanced" ]] && command -v vim &>/dev/null; then
                success "vim already installed"
                continue
            fi
            if _linux_pkg_install "$pkg" 2>/dev/null; then
                success "$pkg installed/present"
            else
                warn "Package not available via dnf/yum: $pkg"
            fi
        done
    fi

    _install_fzf_linux || true
    _install_ripgrep_linux || true
}

# --- Check Vim version ---
check_vim_version() {
    local version_output
    version_output=$(vim --version 2>/dev/null | head -1)

    # Extract major.minor.patch version (e.g., "VIM - Vi IMproved 9.1" -> 9.1)
    local version
    version=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+' | head -1)

    local major minor
    major=$(echo "$version" | cut -d. -f1)
    minor=$(echo "$version" | cut -d. -f2)

    # coc.nvim requires at least Vim 8.1.1719
    # We check: 9.x is OK, 8.2+ is OK, 8.1.1719+ is OK
    if [ "$major" -ge 9 ]; then
        echo "ok"
    elif [ "$major" -eq 8 ]; then
        if [ "$minor" -ge 2 ]; then
            echo "ok"
        elif [ "$minor" -eq 1 ]; then
            # For 8.1.x, we need patch 1719+, but we'll just warn
            warn "Vim 8.1 detected. coc.nvim requires 8.1.1719+"
            echo "warn"
        else
            echo "old"
        fi
    else
        echo "old"
    fi
}

# --- Install Nerd Font ---
install_nerd_font_macos() {
    if ! command -v brew &>/dev/null; then
        warn "Homebrew not found, skipping font installation"
        return 1
    fi

    local font_name="font-meslo-lg-nerd-font"
    if brew list --cask "$font_name" &>/dev/null; then
        success "Font $font_name already installed"
    else
        info "Installing $font_name via Homebrew..."
        brew install --cask "$font_name"
        success "Font installed"
    fi
    return 0
}

install_nerd_font_linux() {
    local font_dir="$HOME/.local/share/fonts"
    local font_installed=false

    # Check if font already exists
    if fc-list 2>/dev/null | grep -qi "MesloLGS NF"; then
        success "MesloLGS NF font already installed"
        return 0
    fi

    info "Installing MesloLGS Nerd Font..."

    # Create font directory
    mkdir -p "$font_dir"

    # Download MesloLGS Nerd Font from powerlevel10k-media repo
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
            if curl -fLo "$target" "$base_url/$font" 2>/dev/null; then
                font_installed=true
            else
                warn "Failed to download $font_name"
            fi
        fi
    done

    # Rebuild font cache
    if [ "$font_installed" = true ]; then
        fc-cache -f "$font_dir" 2>/dev/null || warn "fc-cache not available, you may need to restart your terminal"
        success "MesloLGS Nerd Font installed"
    fi
    return 0
}

install_nerd_font() {
    info "Checking Nerd Font..."
    case "$OS" in
        Darwin)
            install_nerd_font_macos
            ;;
        Linux)
            install_nerd_font_linux
            ;;
        *)
            warn "Unsupported OS: $OS, skipping font installation"
            warn "Please install a Nerd Font manually: https://www.nerdfonts.com/"
            return 1
            ;;
    esac

    echo ""
    echo -e "\033[33m[重要提示]\033[0m 请在终端设置中将字体更改为 'MesloLGS NF' 以正确显示图标"
    echo ""
}

# --- Install system dependencies ---
info "Detected OS: $OS"
case "$OS" in
    Darwin) install_deps_macos ;;
    Linux)  install_deps_linux ;;
    *)      warn "Unknown OS: $OS. Skipping dependency installation." ;;
esac

# --- Check Vim version for coc.nvim ---
VIM_STATUS=$(check_vim_version)
if [ "$VIM_STATUS" = "old" ]; then
    warn "Vim version too old for coc.nvim (requires 8.1.1719+)"
    warn "coc.nvim will be skipped. Consider upgrading Vim to 9.0+"
    SKIP_COC=1
elif [ "$VIM_STATUS" = "warn" ]; then
    warn "Vim version may be too old for some coc.nvim features"
fi

# --- Install vimrc (copy; overwrite with backup) ---
if [ -L "$HOME/.vimrc" ]; then
    info "Removing existing symlink ~/.vimrc"
    rm -f "$HOME/.vimrc"
elif [ -f "$HOME/.vimrc" ]; then
    BACKUP="$HOME/.vimrc.bak.$(date +%Y%m%d%H%M%S)"
    info "Backing up existing ~/.vimrc to $BACKUP"
    cp "$HOME/.vimrc" "$BACKUP"
fi

info "Installing vimrc..."
cp "$SCRIPT_DIR/vimrc" "$HOME/.vimrc"
success "vimrc installed to ~/.vimrc"

# --- Create cache directories ---
mkdir -p "$HOME/.vim/gutentags"

# --- Install vim-plug and plugins ---
info "Installing vim-plug..."
curl -fLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
success "vim-plug installed"

info "Installing Vim plugins (this may take a moment)..."
vim +PlugInstall +qall 2>/dev/null
success "Vim plugins installed"

# --- Install Nerd Font ---
install_nerd_font

# --- Install coc.nvim language servers via npm (non-interactive) ---
if [ "${SKIP_COC:-0}" = "1" ]; then
    warn "Skipping coc.nvim installation due to Vim version"
    warn "To use coc.nvim, upgrade Vim to 9.0+ and run: vim +PlugInstall +qall"
else
    info "Installing coc.nvim language servers..."
    EXTENSIONS=(
        "coc-pyright"
        "coc-go"
        "coc-java"
        "coc-sh"
        "coc-json"
        "coc-yaml"
    )

    install_coc_extensions "${EXTENSIONS[@]}"
fi

# --- Done ---
echo ""
success "Vim setup complete!"
echo ""
echo "  Quick Reference:"
echo "  ,-n        Toggle file tree (NERDTree)"
echo "  ,-t        Toggle tag sidebar (Tagbar)"
echo "  ,-p        Fuzzy find files (FZF)"
echo "  ,-g        Ripgrep search (FZF)"
echo "  gd         Go to definition"
echo "  gr         Find references"
echo "  K          Show documentation"
echo "  ,-gs       Git status"
echo "  ,-gb       Git blame"
echo "  ,-gd       Git diff"
echo "  Tab        Copilot AI suggestion (or coc completion list)"
echo "  Ctrl+]     Accept next word of Copilot suggestion"
echo "  Ctrl+E     Dismiss Copilot suggestion"
echo ""
echo "  Leader key is comma (,)"
echo ""
echo "  Font: Set terminal font to 'MesloLGS NF' for proper icon display"
echo ""
echo "  AI Completion Setup:"
echo "  Run ':Copilot setup' inside Vim to authenticate GitHub Copilot"
echo "  (Free alternative: switch to Codeium in vimrc, then ':Codeium Auth')"
echo ""

