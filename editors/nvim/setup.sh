#!/usr/bin/env bash
# ============================================================
# Neovim Setup Script
# Installs Neovim and configures with lazy.nvim plugins
# ============================================================

set -euo pipefail

info()    { echo -e "\033[34m[INFO]\033[0m $1"; }
success() { echo -e "\033[32m[OK]\033[0m $1"; }
warn()    { echo -e "\033[33m[WARN]\033[0m $1"; }
error()   { echo -e "\033[31m[ERROR]\033[0m $1"; }
step()    { echo -e "\033[36m[STEP]\033[0m $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NVIM_CONFIG_DIR="$HOME/.config/nvim"
# Linux tarball 固定 v0.10.4：兼容 Alinux 3 / glibc 2.32；不用 AppImage（需 FUSE/fusermount）
NVIM_VERSION="${NVIM_VERSION:-0.10.4}"
# Some distros (e.g. Alibaba Cloud Linux 4) ship no `ripgrep` package at all;
# keep a GitHub-release fallback so `rg` is still installed there.
RG_VERSION="${RG_VERSION:-14.1.1}"
CACHE_DIR="${DEVTOOLS_CACHE_DIR:-${SCRIPT_DIR}/../../cache}"
NVIM_INSTALL_DIR="${NVIM_INSTALL_DIR:-$HOME/.local/nvim}"
CONFIG_MARKER=".devtools-nvim"
# Image / CI builds set this so a partial Lazy sync fails the run instead of
# leaving only lazy.nvim and triggering a full install on first file open.
NVIM_SETUP_STRICT="${NVIM_SETUP_STRICT:-0}"
NVIM_SETUP_QUIET="${NVIM_SETUP_QUIET:-0}"

# --- Help ---
show_help() {
    cat <<EOF
Neovim Setup Script - 一键配置 Neovim 开发环境

该脚本会执行以下配置:
  1. 安装/更新 Neovim (Linux 固定 tarball v${NVIM_VERSION}，兼容 glibc 2.32+，无 FUSE 依赖)
     - macOS 通过 Homebrew 安装
     - Linux 优先 cache/binaries/，否则下载官方 tarball；失败再试包管理器
  2. 安装依赖: node, npm, ripgrep, fd, git
  3. 备份已有的 Neovim 配置 (如果存在)
  4. 安装 lazy.nvim 插件管理器
  5. 配置 init.lua 和 lua/ 目录
  6. 自动安装所有插件和 LSP 语言服务器
  7. 安装 Nerd Font 字体 (用于图标显示)

用法:
  ./setup.sh              运行完整安装
  ./setup.sh --backup     备份现有配置到当前目录
  ./setup.sh --update     同步 init.lua/lua/ 配置并更新插件与 LSP
  ./setup.sh --help       显示此帮助信息

环境变量:
  NVIM_VERSION         Linux tarball 版本（默认 ${NVIM_VERSION}）
  NVIM_INSTALL_DIR     Linux 解压目录（默认 ~/.local/nvim）
  DEVTOOLS_CACHE_DIR   离线缓存根目录（默认仓库 cache/）
  NVIM_SETUP_STRICT    设为 1 时，插件 / treesitter 同步失败则退出（镜像构建）
  NVIM_SETUP_QUIET     设为 1 时，headless sync 不刷进度（避免 BuildKit / Bazel 1MiB 日志上限）
  NVIM_SETUP_SKIP_TREESITTER  设为 1 时跳过 TSUpdateSync（E2E ops 不依赖 parser）
  NVIM_SETUP_SKIP_MASON       设为 1 时跳过 MasonToolsInstallSync（E2E ops 不依赖 LSP）
EOF
    # Keep keybindings in a separate literal block for readability
    cat <<'EOF'

快捷键速查 (Leader 键为空格 <Space>):
  <Space>n     切换文件树 (nvim-tree)
  <Space>e     显示诊断浮窗 (diagnostic float)
  <Space>ff    模糊查找文件 (Telescope)
  <Space>fg    全局搜索 (Telescope live_grep)
  <Space>fb    列出缓冲区 (Telescope buffers)
  gd           跳转到定义
  gr           查找引用
  K            显示文档
  <Space>rn    重命名符号
  <Space>ca    代码操作
  <Space>cf    格式化当前文件 (conform，保存时自动格式化)
  <Space>o     代码大纲 (aerial)
  <Space>sr    全项目搜索替换 (grug-far)
  <Space>gs    Git status
  <Space>gb    Git blame
  <Space>gd    Git diff
  <Space>gg    打开 LazyGit
  <C-\>        切换内置终端 (toggleterm)
  F5/F9/F10/F11  调试: 继续 / 断点 / 单步跳过 / 步入 (nvim-dap)
  <Space>tt    运行光标处测试 (neotest)
  <Tab>        确认 cmp / 接受 Copilot 幽灵字 / 缩进 (插入模式)
  <CR>         确认 cmp / 接受 Copilot 幽灵字 / 换行 (插入模式)
  <C-S-g>      关闭 cmp 并请求 Copilot 建议 (插入模式)
  <C-j>        直接接受 Copilot 建议 (插入模式，需先 :Copilot auth)
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

_nvim_linux_arch_asset() {
    case "$(uname -m)" in
        aarch64|arm64) echo "linux-arm64" ;;
        *)             echo "linux-x86_64" ;;
    esac
}

_ensure_local_bin_path() {
    mkdir -p "$HOME/.local/bin"
    if [[ ":${PATH}:" != *":$HOME/.local/bin:"* ]]; then
        if [[ -f "$HOME/.bashrc" ]] || [[ ! -e "$HOME/.bashrc" ]]; then
            if ! grep -qF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" 2>/dev/null; then
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
            fi
        fi
        if [[ -f "$HOME/.zshrc" ]]; then
            if ! grep -qF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zshrc" 2>/dev/null; then
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
            fi
        fi
        export PATH="$HOME/.local/bin:$PATH"
    fi
}

# Run a Neovim Ex command headlessly. Always quote multi-word +cmd / -c args —
# unquoted `+Lazy! sync` is split by the shell, so Lazy never runs.
_nvim_quiet() {
    [[ "${NVIM_SETUP_QUIET:-}" == "1" || "${NVIM_SETUP_QUIET:-}" == "true" ]]
}

_nvim_skip_treesitter() {
    [[ "${NVIM_SETUP_SKIP_TREESITTER:-}" == "1" || "${NVIM_SETUP_SKIP_TREESITTER:-}" == "true" ]]
}

_nvim_skip_mason() {
    [[ "${NVIM_SETUP_SKIP_MASON:-}" == "1" || "${NVIM_SETUP_SKIP_MASON:-}" == "true" ]]
}

_nvim_headless() {
    local cmd="$1"
    local log
    if _nvim_quiet; then
        log="$(mktemp "${TMPDIR:-/tmp}/nvim-setup.XXXXXX")"
        if nvim --headless -c "$cmd" -c "qa!" >"$log" 2>&1; then
            rm -f "$log"
            return 0
        fi
        tail -n 50 "$log" >&2 || true
        rm -f "$log"
        return 1
    fi
    nvim --headless -c "$cmd" -c "qa!"
}

_nvim_strict() {
    [[ "$NVIM_SETUP_STRICT" == "1" || "$NVIM_SETUP_STRICT" == "true" ]]
}

_lazy_root() {
    echo "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy"
}

# Drop plugins whose pinned tag/branch differs from upstream's default, so Lazy
# re-clones them instead of keeping an incompatible checkout.
_reset_pinned_plugins() {
    local lazy_root
    lazy_root="$(_lazy_root)"
    rm -rf \
        "${lazy_root}/mason.nvim" \
        "${lazy_root}/mason-lspconfig.nvim" \
        "${lazy_root}/nvim-lspconfig" \
        "${lazy_root}/nvim-treesitter" \
        "${lazy_root}/lazygit.nvim" \
        "${lazy_root}/aerial.nvim" \
        "${lazy_root}/grug-far.nvim"
}

# Lazy! waits for clones. lua require("lazy").sync() needs a working
# stdpath("cache"); if ~/.cache/nvim is unwritable, setup() aborts and
# sync() then errors on a nil headless field.
_LAZY_SYNC_CMD='Lazy! sync'

_assert_lazy_plugins_installed() {
    local lazy_root name count
    lazy_root="$(_lazy_root)"
    local required=(
        lazy.nvim
        tokyonight.nvim
        nvim-treesitter
        nvim-lspconfig
        mason.nvim
        telescope.nvim
        nvim-cmp
        nvim-tree.lua
    )
    for name in "${required[@]}"; do
        if [[ ! -d "${lazy_root}/${name}" ]]; then
            error "nvim plugin missing after sync: ${name}"
            return 1
        fi
    done
    count="$(find "$lazy_root" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
    if [[ "$count" -lt 40 ]]; then
        error "nvim plugin count too low after sync: ${count} (expected >= 40)"
        return 1
    fi
}

_sync_lazy_plugins() {
    info "Syncing lazy.nvim plugins..."
    _reset_pinned_plugins
    if _nvim_headless "${_LAZY_SYNC_CMD}"; then
        success "Plugins synced"
    else
        if _nvim_strict; then
            error "Lazy sync failed"
            exit 1
        fi
        warn "Lazy sync reported errors; open nvim and run :Lazy sync if needed"
        return 0
    fi
    if ! _assert_lazy_plugins_installed; then
        if _nvim_strict; then
            exit 1
        fi
        warn "some nvim plugins are missing; open nvim and run :Lazy sync"
    fi
}

_sync_treesitter_parsers() {
    if _nvim_skip_treesitter; then
        info "Skipping treesitter parsers (NVIM_SETUP_SKIP_TREESITTER=1)"
        return 0
    fi
    info "Installing treesitter parsers..."
    if _nvim_headless "TSUpdateSync"; then
        success "Treesitter parsers installed"
    else
        if _nvim_strict; then
            error "TSUpdateSync failed"
            exit 1
        fi
        warn "TSUpdateSync reported errors; open nvim and run :TSUpdate"
    fi
}

_mason_packages_root() {
    echo "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/mason/packages"
}

# MasonToolsInstallSync only waits on mason-tool-installer. Confirm the
# common LSPs actually landed so gd/gr work on first file open.
_assert_mason_lsps_installed() {
    local mason_root name
    mason_root="$(_mason_packages_root)"
    local required=(
        bash-language-server
        lua-language-server
        pyright
        json-lsp
        yaml-language-server
        typescript-language-server
    )
    for name in "${required[@]}"; do
        if [[ ! -d "${mason_root}/${name}" ]]; then
            error "mason package missing after install: ${name}"
            return 1
        fi
    done
}

_install_mason_tools() {
    if _nvim_skip_mason; then
        info "Skipping Mason tools (NVIM_SETUP_SKIP_MASON=1)"
        return 0
    fi
    info "Installing Mason tools (formatters / ensured LSPs)..."
    if _nvim_headless "MasonToolsInstallSync"; then
        success "Mason tools installed"
    else
        if _nvim_strict; then
            error "MasonToolsInstallSync failed"
            exit 1
        fi
        warn "MasonToolsInstallSync reported errors; use :Mason if needed"
        return 0
    fi
    if ! _assert_mason_lsps_installed; then
        if _nvim_strict; then
            exit 1
        fi
        warn "some mason LSPs are missing; open nvim and run :Mason"
    fi
}

install_nvim_linux() {
    local current_version
    current_version="$(get_nvim_version)"

    if [ "$(version_compare "$current_version" "0.9.0")" != "lt" ]; then
        success "Neovim $current_version already installed"
        return 0
    fi

    info "Installing Neovim v${NVIM_VERSION} via tarball..."

    local arch_asset filename cached url archive_path extract_dir top_dir nvim_bin
    arch_asset="$(_nvim_linux_arch_asset)"
    filename="nvim-${arch_asset}-v${NVIM_VERSION}.tar.gz"
    cached="${CACHE_DIR}/binaries/${filename}"
    url="https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-${arch_asset}.tar.gz"
    extract_dir="$(mktemp -d "${TMPDIR:-/tmp}/nvim-extract.XXXXXX")"
    archive_path="${extract_dir}/${filename}"

    _ensure_local_bin_path

    if [[ -f "$cached" ]]; then
        info "Using local cache: binaries/${filename}"
        cp "$cached" "$archive_path"
    elif curl -fL --retry 3 -o "$archive_path" "$url"; then
        info "Downloaded Neovim v${NVIM_VERSION} tarball"
    else
        rm -rf "$extract_dir"
        warn "Failed to download tarball, trying package manager..."
        install_nvim_linux_package_manager
        return 0
    fi

    if ! tar -xzf "$archive_path" -C "$extract_dir"; then
        rm -rf "$extract_dir"
        warn "Failed to extract Neovim tarball, trying package manager..."
        install_nvim_linux_package_manager
        return 0
    fi

    top_dir="${extract_dir}/nvim-${arch_asset}"
    nvim_bin="${top_dir}/bin/nvim"
    if [[ ! -x "$nvim_bin" ]]; then
        rm -rf "$extract_dir"
        error "Neovim tarball missing bin/nvim"
        exit 1
    fi

    rm -rf "$NVIM_INSTALL_DIR"
    mkdir -p "$(dirname "$NVIM_INSTALL_DIR")"
    mv "$top_dir" "$NVIM_INSTALL_DIR"
    ln -sfn "$NVIM_INSTALL_DIR/bin/nvim" "$HOME/.local/bin/nvim"
    rm -rf "$extract_dir"

    success "Neovim tarball installed to $NVIM_INSTALL_DIR (symlink ~/.local/bin/nvim)"
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
    # tree-sitter-cli: nvim-treesitter main branch (rewrite, nvim 0.12+) builds
    # parsers with `tree-sitter generate` + cc; brew is always 0.12+. Note the
    # `tree-sitter` formula ships only the C library, not the CLI.
    # go: mason-lspconfig auto-installs gopls via `go install`, so Go must exist.
    local deps=(node npm ripgrep fd git tree-sitter-cli go)
    for dep in "${deps[@]}"; do
        if brew list "$dep" &>/dev/null 2>/dev/null; then
            success "$dep already installed"
        else
            info "Installing $dep..."
            brew install "$dep" || warn "Failed to install $dep"
        fi
    done
}

# Some package managers (dnf on Alibaba Cloud Linux 4, in particular) have no
# `ripgrep` package at all, so `rg` stays missing after install_deps_linux.
# Fall back to the same cache-first / GitHub-release tarball used for Neovim.
_install_ripgrep_github_fallback() {
    if command -v rg &>/dev/null; then
        return 0
    fi
    info "ripgrep not available via package manager, installing v${RG_VERSION} from cache/GitHub release..."

    local target filename cached url tmpdir rg_bin
    case "$(uname -m)" in
        aarch64|arm64) target="aarch64-unknown-linux-musl" ;;
        *)             target="x86_64-unknown-linux-musl" ;;
    esac
    filename="ripgrep-${RG_VERSION}-${target}.tar.gz"
    cached="${CACHE_DIR}/binaries/${filename}"
    url="https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/${filename}"
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/rg-extract.XXXXXX")"

    _ensure_local_bin_path

    if [[ -f "$cached" ]]; then
        info "Using local cache: binaries/${filename}"
        cp "$cached" "$tmpdir/rg.tar.gz"
    elif ! curl -fL --retry 3 -o "$tmpdir/rg.tar.gz" "$url"; then
        rm -rf "$tmpdir"
        warn "Failed to download ripgrep release; rg will remain unavailable"
        return 1
    fi

    if ! tar -xzf "$tmpdir/rg.tar.gz" -C "$tmpdir"; then
        rm -rf "$tmpdir"
        warn "Failed to extract ripgrep release; rg will remain unavailable"
        return 1
    fi

    rg_bin="${tmpdir}/ripgrep-${RG_VERSION}-${target}/rg"
    if [[ ! -x "$rg_bin" ]]; then
        rm -rf "$tmpdir"
        warn "ripgrep release archive missing rg binary"
        return 1
    fi
    install -m 755 "$rg_bin" "$HOME/.local/bin/rg"
    rm -rf "$tmpdir"
    success "ripgrep installed to ~/.local/bin/rg"
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

    _install_ripgrep_github_fallback || true
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

# --- Update: sync config files, then refresh plugins and LSP servers ---
update_all() {
    if ! command -v nvim &>/dev/null; then
        error "Neovim not found"
        exit 1
    fi

    sync_config
    _sync_lazy_plugins
    _sync_treesitter_parsers

    step "Updating LSP servers..."
    if _nvim_headless "MasonToolsUpdateSync"; then
        success "LSP servers updated"
    else
        warn "MasonToolsUpdateSync reported errors"
    fi
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

# --- Sync configuration ---
# Idempotent: an unmanaged config is backed up once, then the marker lets later
# runs overwrite in place instead of piling up ~/.config/nvim.bak.* directories.
sync_config() {
    step "Syncing Neovim configuration..."

    if [ ! -f "$SCRIPT_DIR/init.lua" ]; then
        error "init.lua not found in $SCRIPT_DIR"
        exit 1
    fi

    if [ -L "$NVIM_CONFIG_DIR" ]; then
        rm "$NVIM_CONFIG_DIR"
    elif [ -d "$NVIM_CONFIG_DIR" ] && [ ! -f "$NVIM_CONFIG_DIR/$CONFIG_MARKER" ]; then
        local backup="$NVIM_CONFIG_DIR.bak.$(date +%Y%m%d%H%M%S)"
        info "Backing up existing config to $backup"
        mv "$NVIM_CONFIG_DIR" "$backup"
    fi

    mkdir -p "$NVIM_CONFIG_DIR"

    # Drop the managed lua/ tree so renamed or deleted modules do not linger.
    rm -rf "$NVIM_CONFIG_DIR/lua"
    cp "$SCRIPT_DIR/init.lua" "$NVIM_CONFIG_DIR/"
    if [ -d "$SCRIPT_DIR/lua" ]; then
        cp -r "$SCRIPT_DIR/lua" "$NVIM_CONFIG_DIR/"
    fi
    echo "managed by devtools editors/nvim/setup.sh" > "$NVIM_CONFIG_DIR/$CONFIG_MARKER"

    success "Configuration synced to $NVIM_CONFIG_DIR"
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

    # Sync configuration
    sync_config

    # Install Nerd Font
    install_nerd_font

    # First run to install plugins (lua sync waits; see _LAZY_SYNC_LUA)
    step "Installing plugins (this may take a few minutes)..."
    _sync_lazy_plugins

    step "Installing treesitter parsers..."
    _sync_treesitter_parsers

    step "Installing LSP servers..."
    _install_mason_tools

    # Done
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         Neovim 配置完成!  (Setup Complete!)                ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    success "Neovim is ready to use!"
    echo ""
    echo "快速参考 (Quick Reference):"
    echo "  <Space>n     切换文件树 (nvim-tree)"
    echo "  <Space>e     显示诊断浮窗 (diagnostic float)"
    echo "  <Space>ff    模糊查找文件 (Telescope)"
    echo "  <Space>fg    全局搜索 (Telescope live_grep)"
    echo "  <Space>fb    列出缓冲区 (Telescope buffers)"
    echo "  gd           跳转到定义 (Go to definition)"
    echo "  gr           查找引用 (Find references)"
    echo "  K            显示文档 (Show documentation)"
    echo "  <Space>rn    重命名符号 (Rename symbol)"
    echo "  <Space>ca    代码操作 (Code action)"
    echo "  <Space>cf    格式化 (保存时自动格式化)"
    echo "  <Space>o     代码大纲 (Outline)"
    echo "  <Space>tt    运行测试 (Test)"
    echo "  F5 / F9      调试: 继续 / 断点 (Debug)"
    echo "  <C-\\>        内置终端 (Terminal)"
    echo "  <Space>gg    打开 LazyGit"
    echo ""
    echo "  启动命令: nvim"
    echo ""
    echo "  提示: 将终端字体设置为 'MesloLGS NF' 以显示图标"
    echo "  提示: 首次使用 GitHub Copilot 需在 nvim 内运行 :Copilot auth 完成登录（需订阅）"
    echo ""
}

# --- Parse arguments ---
if [[ "${SETUP_NO_MAIN:-}" != "1" && "${SETUP_NO_MAIN:-}" != "true" ]]; then
    case "${1:-}" in
        --help|-h)      show_help ;;
        --backup|-b)    backup_config ;;
        --update|-u)    update_all ;;
        "")             main ;;
        *)
            error "Unknown option: ${1:-}"
            echo "Run ./setup.sh --help for usage" >&2
            exit 1
            ;;
    esac
fi
