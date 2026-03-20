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
  1. 安装系统依赖 (vim, node, universal-ctags, fzf, ripgrep)
     - macOS 通过 Homebrew 安装
     - Linux 通过 apt-get 或 yum 安装
  2. 备份已有的 ~/.vimrc (如果存在)
  3. 将本目录的 vimrc 软链接到 ~/.vimrc
  4. 创建 Vim 缓存目录 (~/.vim/gutentags)
  5. 安装 vim-plug 插件管理器并安装所有插件
  6. 安装 coc.nvim 语言服务器 (Python, Go, Java, Shell, JSON, YAML)

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
  Tab/S-Tab  补全导航
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

    # Backup existing ~/.vimrc if it exists and is not a symlink
    if [ -f "$HOME/.vimrc" ] && [ ! -L "$HOME/.vimrc" ]; then
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

    # Install coc.nvim language servers
    info "Installing coc.nvim language servers..."
    EXTENSIONS=(
        "coc-pyright"
        "coc-go"
        "coc-java"
        "coc-sh"
        "coc-json"
        "coc-yaml"
    )

    mkdir -p "$HOME/.config/coc/extensions"

    for ext in "${EXTENSIONS[@]}"; do
        info "Installing $ext..."
        vim -c "CocInstall -sync $ext" -c "qall" 2>/dev/null || warn "Failed to install $ext (install manually in vim with :CocInstall $ext)"
    done
    success "Language servers configured"

    echo ""
    success "Vim restore complete!"
    exit 0
}

case "${1:-}" in
    --help|-h)     show_help ;;
    --backup|-b)   backup_vimrc ;;
    --restore|-r)  restore_vimrc ;;
esac

# --- Detect OS ---
OS="$(uname -s)"

install_deps_macos() {
    info "Installing dependencies via Homebrew..."
    if ! command -v brew &>/dev/null; then
        error "Homebrew not found. Install it first: https://brew.sh"
        exit 1
    fi

    local deps=(vim node universal-ctags fzf ripgrep)
    for dep in "${deps[@]}"; do
        if brew list "$dep" &>/dev/null; then
            success "$dep already installed"
        else
            info "Installing $dep..."
            brew install "$dep"
        fi
    done
}

install_deps_linux() {
    info "Installing dependencies via package manager..."

    if command -v apt-get &>/dev/null; then
        sudo apt-get update
        sudo apt-get install -y vim nodejs npm universal-ctags fzf ripgrep curl git
    elif command -v yum &>/dev/null; then
        sudo yum install -y vim nodejs npm ctags fzf ripgrep curl git
    else
        error "Unsupported package manager. Install manually: vim, nodejs, npm, ctags, fzf, ripgrep"
        exit 1
    fi
}

# --- Install system dependencies ---
info "Detected OS: $OS"
case "$OS" in
    Darwin) install_deps_macos ;;
    Linux)  install_deps_linux ;;
    *)      warn "Unknown OS: $OS. Skipping dependency installation." ;;
esac

# --- Backup existing vimrc ---
if [ -f "$HOME/.vimrc" ] && [ ! -L "$HOME/.vimrc" ]; then
    BACKUP="$HOME/.vimrc.bak.$(date +%Y%m%d%H%M%S)"
    info "Backing up existing ~/.vimrc to $BACKUP"
    cp "$HOME/.vimrc" "$BACKUP"
fi

# --- Link vimrc ---
info "Linking vimrc..."
ln -sf "$SCRIPT_DIR/vimrc" "$HOME/.vimrc"
success "~/.vimrc -> $SCRIPT_DIR/vimrc"

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

# --- Install coc.nvim language servers ---
info "Installing coc.nvim language servers..."
EXTENSIONS=(
    "coc-pyright"
    "coc-go"
    "coc-java"
    "coc-sh"
    "coc-json"
    "coc-yaml"
)

mkdir -p "$HOME/.config/coc/extensions"

for ext in "${EXTENSIONS[@]}"; do
    info "Installing $ext..."
    vim -c "CocInstall -sync $ext" -c "qall" 2>/dev/null || warn "Failed to install $ext (install manually in vim with :CocInstall $ext)"
done
success "Language servers configured"

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
echo "  Tab/S-Tab  Navigate completion"
echo ""
echo "  Leader key is comma (,)"
echo ""

