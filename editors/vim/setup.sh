#!/bin/bash
# ============================================================
# Vim Setup Script
# Installs vimrc, vim-plug, and required system dependencies
# ============================================================

set -euo pipefail

info()    { echo -e "\033[34m[INFO]\033[0m $1"; }
success() { echo -e "\033[32m[OK]\033[0m $1"; }
warn()    { echo -e "\033[33m[WARN]\033[0m $1"; }
error()   { echo -e "\033[31m[ERROR]\033[0m $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Pinned upgrade target (override via env). Tags on github.com/vim/vim.
VIM_9_TARGET="${VIM_9_TARGET:-9.2.0782}"
# coc.nvim's release build refuses to start below this Node version.
COC_NODE_MIN="${COC_NODE_MIN:-22.15.0}"
VIM_PREFIX="${VIM_PREFIX:-$HOME/.local}"
CACHE_DIR="${DEVTOOLS_CACHE_DIR:-${SCRIPT_DIR}/../../cache}"

DRY_RUN=false
DO_UPGRADE=false
DO_BACKUP=false
DO_RESTORE=false

# --- Help ---
show_help() {
    cat <<EOF
Vim Setup Script - 一键配置 Vim 开发环境

该脚本会执行以下配置:
  1. 安装系统依赖 (vim, node, ctags, fzf, ripgrep)
     - macOS 通过 Homebrew 安装
     - Linux 通过 apt-get / dnf / yum 安装；fzf、ripgrep 在仓库缺失时
       自动回退到 GitHub 二进制（优先 cache/，安装到 ~/.local/bin）
  2. 检测 Vim 版本 (coc.nvim 需要 Vim 8.1.1719+)
     - 使用 --upgrade 时：统一升级到 ${VIM_9_TARGET}
       优先包管理器，仍不足则源码安装到 ~/.local
  3. 备份已有的 ~/.vimrc (如果存在)
  4. 将本目录的 vimrc 复制到 ~/.vimrc（覆盖）
  5. 创建 Vim 缓存目录 (~/.vim/gutentags)
  6. 安装 vim-plug 插件管理器并安装所有插件
  7. 安装 Nerd Font 字体 (用于 NERDTree 等插件显示图标)
  8. 安装 coc.nvim 语言服务器 (Python, Go, Java, Shell, JSON, YAML)
     - 如果 Vim 版本过低则跳过此步骤（除非 --upgrade 成功）

用法:
  ./setup.sh              运行完整安装
  ./setup.sh --upgrade    升级 Vim 到 ${VIM_9_TARGET} 后完整安装
  ./setup.sh --dry-run    试运行，只显示将要执行的操作
  ./setup.sh --backup     将 ~/.vimrc 备份到当前目录的 vimrc
  ./setup.sh --restore    将当前目录的 vimrc 覆盖到 ~/.vimrc 并安装插件
  ./setup.sh --help       显示此帮助信息

环境变量:
  VIM_9_TARGET       --upgrade 目标版本（默认 ${VIM_9_TARGET}）
  VIM_PREFIX         源码安装前缀（默认 \$HOME/.local）
  DEVTOOLS_CACHE_DIR 离线缓存根目录（默认仓库 cache/）

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

run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [试运行] $*"
    else
        "$@"
    fi
}

# --- Argument parsing ---
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)     show_help ;;
            --upgrade|-u)  DO_UPGRADE=true; shift ;;
            --dry-run|-d)  DRY_RUN=true; shift ;;
            --backup|-b)   DO_BACKUP=true; shift ;;
            --restore|-r)  DO_RESTORE=true; shift ;;
            *)
                error "未知选项: $1\n       运行 ./setup.sh --help 查看用法"
                ;;
        esac
    done
}

# --- Backup ~/.vimrc to current directory ---
backup_vimrc() {
    if [ ! -f "$HOME/.vimrc" ]; then
        error "~/.vimrc does not exist, nothing to backup"
    fi

    info "Backing up ~/.vimrc to $SCRIPT_DIR/vimrc..."
    run cp "$HOME/.vimrc" "$SCRIPT_DIR/vimrc"
    success "Backup complete: $SCRIPT_DIR/vimrc"
}

# --- Restore vimrc from current directory and install plugins ---
restore_vimrc() {
    if [ ! -f "$SCRIPT_DIR/vimrc" ]; then
        error "vimrc not found in $SCRIPT_DIR"
    fi

    # Backup regular file; remove symlink first so cp does not write through
    if [ -L "$HOME/.vimrc" ]; then
        info "Removing existing symlink ~/.vimrc"
        run rm -f "$HOME/.vimrc"
    elif [ -f "$HOME/.vimrc" ]; then
        BACKUP="$HOME/.vimrc.bak.$(date +%Y%m%d%H%M%S)"
        info "Backing up existing ~/.vimrc to $BACKUP"
        run cp "$HOME/.vimrc" "$BACKUP"
    fi

    info "Restoring vimrc from $SCRIPT_DIR/vimrc..."
    run cp "$SCRIPT_DIR/vimrc" "$HOME/.vimrc"
    success "vimrc restored to ~/.vimrc"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[试运行] 将安装插件、coc 扩展与 Nerd Font"
        return 0
    fi

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
}

# --- Install coc.nvim extensions ---
install_coc_extensions() {
    local extensions=("$@")
    local ext_dir="$HOME/.config/coc/extensions"

    mkdir -p "$ext_dir"

    # Create package.json if missing (required for npm to manage deps correctly)
    if [ ! -f "$ext_dir/package.json" ]; then
        echo '{"dependencies":{}}' > "$ext_dir/package.json"
    fi

    (
        cd "$ext_dir"

        local ext
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
    )
    success "Language servers configured"
}

# --- Detect OS ---
detect_os() {
    OS="$(uname -s)"
}

install_deps_macos() {
    info "Installing dependencies via Homebrew..."
    if ! command -v brew &>/dev/null; then
        error "Homebrew not found. Install it first: https://brew.sh"
    fi

    local deps=(vim node ctags fzf ripgrep)
    local dep
    for dep in "${deps[@]}"; do
        if brew list "$dep" &>/dev/null; then
            success "$dep already installed"
        else
            info "Installing $dep..."
            run brew install "$dep"
        fi
    done
}

# Install a package via the detected Linux package manager; return non-zero on miss.
_linux_pkg_install() {
    local pkg="$1"
    if command -v apt-get &>/dev/null; then
        run sudo apt-get install -y "$pkg"
    elif command -v dnf &>/dev/null; then
        run sudo dnf install -y "$pkg"
    elif command -v yum &>/dev/null; then
        run sudo yum install -y "$pkg"
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

# Ensure ~/.local/bin is on PATH for this process and common shell rc files (idempotent).
ensure_local_path() {
    local bindir="${VIM_PREFIX}/bin"
    [[ "$bindir" == "$HOME/.local/bin" ]] || {
        mkdir -p "$bindir"
        case ":$PATH:" in
            *":${bindir}:"*) ;;
            *) export PATH="${bindir}:$PATH" ;;
        esac
        return 0
    }

    _ensure_local_bin

    local marker="# managed by editors/vim/setup.sh"
    local line='export PATH="$HOME/.local/bin:$PATH"'
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$rc" ]] || continue
        if ! grep -qF "$marker" "$rc" 2>/dev/null; then
            info "将 $bindir 写入 $(basename "$rc")"
            if [[ "$DRY_RUN" == "true" ]]; then
                echo "  [试运行] append PATH to $rc"
            else
                printf '\n%s\n%s\n' "$marker" "$line" >> "$rc"
            fi
        fi
    done
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

# True when a dep's command already exists. Skipping it matters for Node:
# apt/dnf would otherwise replace a working NodeSource/nvm Node with the distro
# build, and coc.nvim needs Node >= ${COC_NODE_MIN} (noble ships 18.19.1).
_dep_already_present() {
    case "$1" in
        nodejs)           command -v node &>/dev/null ;;
        npm)              command -v npm &>/dev/null ;;
        vim|vim-enhanced) command -v vim &>/dev/null ;;
        *)                return 1 ;;
    esac
}

install_deps_linux() {
    info "Installing dependencies via package manager..."

    if command -v apt-get &>/dev/null; then
        run sudo apt-get update
    elif ! command -v dnf &>/dev/null && ! command -v yum &>/dev/null; then
        error "Unsupported package manager. Install manually: vim, nodejs, npm, ctags, fzf, ripgrep"
    fi

    # Install packages individually so missing names (common on Alinux/RHEL) do not abort.
    local pkg
    if command -v apt-get &>/dev/null; then
        for pkg in vim nodejs npm universal-ctags curl git; do
            if _dep_already_present "$pkg"; then
                success "$pkg already present"
                continue
            fi
            if _linux_pkg_install "$pkg" 2>/dev/null; then
                success "$pkg installed/present"
            else
                warn "Failed to install $pkg via apt-get"
            fi
        done
    else
        # vim-enhanced provides /usr/bin/vim on RHEL-family; plain "vim" may be absent.
        for pkg in vim-enhanced vim nodejs npm ctags curl git; do
            if _dep_already_present "$pkg"; then
                success "$pkg already present"
                continue
            fi
            if _linux_pkg_install "$pkg" 2>/dev/null; then
                success "$pkg installed/present"
            else
                warn "Package not available via dnf/yum: $pkg"
            fi
        done
    fi

    if [[ "$DRY_RUN" != "true" ]]; then
        _install_fzf_linux || true
        _install_ripgrep_linux || true
    else
        info "[试运行] 将安装 fzf / ripgrep（包管理器或 GitHub 二进制）"
    fi
}

# --- Vim version helpers ---
# Returns major.minor.patch (patch defaults to 0). Empty if vim missing.
get_vim_version() {
    if ! command -v vim &>/dev/null; then
        echo ""
        return 0
    fi

    local version_output patch_line version major minor patch
    version_output=$(vim --version 2>/dev/null | head -1 || true)
    version=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
    [[ -n "$version" ]] || { echo ""; return 0; }

    major=$(echo "$version" | cut -d. -f1)
    minor=$(echo "$version" | cut -d. -f2)
    patch=0

    patch_line=$(vim --version 2>/dev/null | grep -E 'Included patches:' | head -1 || true)
    if [[ -n "$patch_line" ]]; then
        # "Included patches: 1-1719" or "Included patches: 1-1234, 1236"
        local last
        last=$(echo "$patch_line" | grep -oE '[0-9]+' | tail -1 || true)
        [[ -n "$last" ]] && patch="$last"
    fi

    echo "${major}.${minor}.${patch}"
}

# Compare dotted versions; echo "ge" if $1 >= $2, else "lt".
version_ge() {
    local a="$1" b="$2"
    local IFS=.
    # shellcheck disable=SC2086
    set -- $a
    local a1="${1:-0}" a2="${2:-0}" a3="${3:-0}"
    # shellcheck disable=SC2086
    set -- $b
    local b1="${1:-0}" b2="${2:-0}" b3="${3:-0}"

    # Force base-10: Vim tags zero-pad patches (e.g. 9.2.0782); ((0782)) is invalid octal.
    a1=$((10#$a1))
    a2=$((10#$a2))
    a3=$((10#$a3))
    b1=$((10#$b1))
    b2=$((10#$b2))
    b3=$((10#$b3))

    if ((a1 > b1)); then echo "ge"; return; fi
    if ((a1 < b1)); then echo "lt"; return; fi
    if ((a2 > b2)); then echo "ge"; return; fi
    if ((a2 < b2)); then echo "lt"; return; fi
    if ((a3 >= b3)); then echo "ge"; return; fi
    echo "lt"
}

# Resolve upgrade target version (no leading v). Always pin to VIM_9_TARGET.
resolve_vim_target() {
    echo "$VIM_9_TARGET"
}

# --- Check Vim version for coc.nvim ---
check_vim_version() {
    local version major minor patch
    version=$(get_vim_version)

    if [[ -z "$version" ]]; then
        echo "old"
        return 0
    fi

    major=$(echo "$version" | cut -d. -f1)
    minor=$(echo "$version" | cut -d. -f2)
    patch=$(echo "$version" | cut -d. -f3)

    # coc.nvim requires at least Vim 8.1.1719
    if [ "$major" -ge 9 ]; then
        echo "ok"
    elif [ "$major" -eq 8 ]; then
        if [ "$minor" -ge 2 ]; then
            echo "ok"
        elif [ "$minor" -eq 1 ]; then
            if [ "${patch:-0}" -ge 1719 ]; then
                echo "ok"
            else
                warn "Vim 8.1 detected (patch ${patch}). coc.nvim requires 8.1.1719+"
                echo "warn"
            fi
        else
            echo "old"
        fi
    else
        echo "old"
    fi
}

# --- Check Node version for coc.nvim ---
# echo ok / old / missing. coc release crashes on older Node and can hang Vim's
# exit, so an unusable Node must skip coc rather than install it.
check_node_version() {
    local ver
    if ! command -v node &>/dev/null; then
        echo "missing"
        return 0
    fi
    ver="$(node -v 2>/dev/null)"
    ver="${ver#v}"
    if [[ ! "$ver" =~ ^[0-9]+\.[0-9]+ ]]; then
        echo "missing"
        return 0
    fi
    if [[ "$(version_ge "$ver" "$COC_NODE_MIN")" == "ge" ]]; then
        echo "ok"
    else
        echo "old"
    fi
}

install_vim_build_deps() {
    info "安装 Vim 编译依赖 (gcc, make, ncurses)..."
    case "$OS" in
        Darwin)
            if ! xcode-select -p &>/dev/null; then
                warn "未检测到 Xcode Command Line Tools；源码编译可能失败"
            fi
            if command -v brew &>/dev/null; then
                run brew install ncurses || true
            fi
            ;;
        Linux)
            if command -v apt-get &>/dev/null; then
                run sudo apt-get update -y
                run sudo apt-get install -y build-essential libncurses-dev curl
            elif command -v dnf &>/dev/null; then
                run sudo dnf install -y gcc make ncurses-devel curl
            elif command -v yum &>/dev/null; then
                run sudo yum install -y gcc make ncurses-devel curl
            else
                error "无法识别的包管理器，请手动安装 gcc/make/ncurses 开发包后重试"
            fi
            ;;
        *)
            error "Unsupported OS: $OS，无法安装编译依赖"
            ;;
    esac
}

upgrade_vim_via_pkg() {
    info "尝试通过包管理器升级 Vim..."
    case "$OS" in
        Darwin)
            if ! command -v brew &>/dev/null; then
                warn "Homebrew 未安装，跳过包管理器升级"
                return 1
            fi
            if brew list vim &>/dev/null; then
                run brew upgrade vim || run brew install vim
            else
                run brew install vim
            fi
            ;;
        Linux)
            if command -v apt-get &>/dev/null; then
                run sudo apt-get update -y
                run sudo apt-get install -y --only-upgrade vim || run sudo apt-get install -y vim
            elif command -v dnf &>/dev/null; then
                run sudo dnf upgrade -y vim-enhanced vim || run sudo dnf install -y vim-enhanced vim
            elif command -v yum &>/dev/null; then
                run sudo yum update -y vim-enhanced vim || run sudo yum install -y vim-enhanced vim
            else
                warn "无法识别的包管理器，跳过包管理器升级"
                return 1
            fi
            ;;
        *)
            warn "Unsupported OS: $OS, 跳过包管理器升级"
            return 1
            ;;
    esac
    hash -r 2>/dev/null || true
    return 0
}

install_vim_from_source() {
    local target="$1"
    local tag="v${target}"
    local tarball="vim-${target}.tar.gz"
    local url="https://github.com/vim/vim/archive/refs/tags/${tag}.tar.gz"
    local cached="${CACHE_DIR}/binaries/${tarball}"
    local tmpdir tarball_path srcdir

    # Idempotent: prefix install already meets target
    if [[ -x "${VIM_PREFIX}/bin/vim" ]]; then
        export PATH="${VIM_PREFIX}/bin:$PATH"
        local local_ver
        local_ver=$(get_vim_version)
        if [[ -n "$local_ver" && "$(version_ge "$local_ver" "$target")" == "ge" ]]; then
            success "Vim ${local_ver} 已满足目标 ${target} (${VIM_PREFIX}/bin/vim)"
            return 0
        fi
    fi

    info "从源码安装 Vim ${target} → ${VIM_PREFIX} ..."
    install_vim_build_deps

    tmpdir=$(mktemp -d)
    tarball_path="${tmpdir}/${tarball}"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmpdir'" RETURN

    if [[ -f "$cached" ]]; then
        info "使用本地缓存: binaries/${tarball}"
        run cp "$cached" "$tarball_path"
    else
        info "下载 Vim ${tag}..."
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [试运行] curl -fL -o $tarball_path $url"
        else
            curl -fL --retry 3 -o "$tarball_path" "$url"
        fi
    fi

    srcdir="${tmpdir}/vim-${target}"
    info "编译安装到 ${VIM_PREFIX} ..."
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [试运行] tar xf $tarball_path && ./configure --prefix=$VIM_PREFIX --with-features=huge --enable-multibyte && make && make install"
        return 0
    fi

    tar xf "$tarball_path" -C "$tmpdir"
    (
        cd "$srcdir"
        ./configure --prefix="$VIM_PREFIX" --with-features=huge --enable-multibyte
        make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
        make install
    )

    [[ -x "${VIM_PREFIX}/bin/vim" ]] || error "安装失败：找不到 ${VIM_PREFIX}/bin/vim"
    success "Vim 已安装: $("${VIM_PREFIX}/bin/vim" --version | head -1) -> ${VIM_PREFIX}/bin/vim"
}

upgrade_vim() {
    local current target
    current=$(get_vim_version)
    target=$(resolve_vim_target)

    if [[ -z "$current" ]]; then
        info "未检测到 Vim → 目标 ${target}"
    else
        info "当前 Vim: ${current} → 目标 ${target}"
        if [[ "$(version_ge "$current" "$target")" == "ge" ]]; then
            success "Vim ${current} 已满足目标 ${target}，跳过升级"
            return 0
        fi
    fi

    # Package manager first (all platforms)
    upgrade_vim_via_pkg || true
    hash -r 2>/dev/null || true
    current=$(get_vim_version)
    if [[ -n "$current" && "$(version_ge "$current" "$target")" == "ge" ]]; then
        success "包管理器升级后 Vim ${current} 已满足目标 ${target}"
        return 0
    fi

    if [[ -n "$current" ]]; then
        warn "包管理器后 Vim 仍为 ${current}（目标 ${target}），回退到源码安装"
    else
        warn "包管理器未能提供足够新的 Vim，回退到源码安装"
    fi

    case "$OS" in
        Darwin)
            # On macOS prefer brew; if still short, build to ~/.local
            install_vim_from_source "$target"
            ;;
        Linux)
            install_vim_from_source "$target"
            ;;
        *)
            error "Unsupported OS: $OS，无法源码安装 Vim"
            ;;
    esac

    ensure_local_path
    export PATH="${VIM_PREFIX}/bin:$PATH"
    hash -r 2>/dev/null || true

    current=$(get_vim_version)
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[试运行] 升级完成后将复检 Vim 版本（目标 ${target}）"
        return 0
    fi

    if [[ -z "$current" || "$(version_ge "$current" "$target")" != "ge" ]]; then
        error "Vim 升级失败：当前 ${current:-none}，目标 ${target}"
    fi
    success "PATH 中的 vim: $(command -v vim) (${current})"
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
        run brew install --cask "$font_name"
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

    local font
    for font in "${fonts[@]}"; do
        local font_name
        font_name=$(echo "$font" | sed 's/%20/ /g')
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

deploy_vimrc() {
    if [ -L "$HOME/.vimrc" ]; then
        info "Removing existing symlink ~/.vimrc"
        run rm -f "$HOME/.vimrc"
    elif [ -f "$HOME/.vimrc" ]; then
        BACKUP="$HOME/.vimrc.bak.$(date +%Y%m%d%H%M%S)"
        info "Backing up existing ~/.vimrc to $BACKUP"
        run cp "$HOME/.vimrc" "$BACKUP"
    fi

    info "Installing vimrc..."
    run cp "$SCRIPT_DIR/vimrc" "$HOME/.vimrc"
    success "vimrc installed to ~/.vimrc"
}

install_plugins_and_coc() {
    local skip_coc="${1:-0}"

    mkdir -p "$HOME/.vim/gutentags"

    info "Installing vim-plug..."
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [试运行] curl vim-plug + vim +PlugInstall"
    else
        curl -fLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
            https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
        success "vim-plug installed"

        info "Installing Vim plugins (this may take a moment)..."
        vim +PlugInstall +qall 2>/dev/null
        success "Vim plugins installed"
    fi

    install_nerd_font

    if [ "$skip_coc" = "1" ]; then
        warn "Skipping coc.nvim installation (Vim < 8.1.1719 or Node < ${COC_NODE_MIN})"
        warn "To use coc.nvim: ./setup.sh --upgrade for Vim, and install Node >= ${COC_NODE_MIN}"
    else
        info "Installing coc.nvim language servers..."
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [试运行] npm install coc extensions"
        else
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
    fi
}

print_done() {
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
}

main() {
    parse_args "$@"
    detect_os

    if [[ "$DO_BACKUP" == "true" ]]; then
        backup_vimrc
        return 0
    fi
    if [[ "$DO_RESTORE" == "true" ]]; then
        restore_vimrc
        return 0
    fi

    info "Detected OS: $OS"
    case "$OS" in
        Darwin) install_deps_macos ;;
        Linux)  install_deps_linux ;;
        *)      warn "Unknown OS: $OS. Skipping dependency installation." ;;
    esac

    local skip_coc=0
    if [[ "$DO_UPGRADE" == "true" ]]; then
        upgrade_vim
        local vim_status
        vim_status=$(check_vim_version)
        if [[ "$DRY_RUN" != "true" && "$vim_status" == "old" ]]; then
            error "Vim 升级后仍过旧，无法安装 coc.nvim（requires 8.1.1719+）"
        fi
        if [[ "$vim_status" == "warn" ]]; then
            warn "Vim version may be too old for some coc.nvim features"
        fi
    else
        local vim_status
        vim_status=$(check_vim_version)
        if [ "$vim_status" = "old" ]; then
            warn "Vim version too old for coc.nvim (requires 8.1.1719+)"
            warn "coc.nvim will be skipped. Consider: ./setup.sh --upgrade"
            skip_coc=1
        elif [ "$vim_status" = "warn" ]; then
            warn "Vim version may be too old for some coc.nvim features"
        fi
    fi

    # coc release needs a recent enough Node too; vimrc gates on the same floor.
    local node_status
    node_status=$(check_node_version)
    if [[ "$node_status" != "ok" ]]; then
        warn "coc.nvim requires Node >= ${COC_NODE_MIN} (node: ${node_status})"
        warn "coc.nvim will be skipped; vimrc falls back to AutoComplPop"
        skip_coc=1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[试运行] 将安装 vimrc、vim-plug 插件与 Nerd Font"
        if [[ "$skip_coc" == "1" ]]; then
            warn "Skipping coc.nvim installation (Vim < 8.1.1719 or Node < ${COC_NODE_MIN})"
            warn "To use coc.nvim: ./setup.sh --upgrade for Vim, and install Node >= ${COC_NODE_MIN}"
        else
            info "[试运行] 将安装 coc.nvim 语言服务器"
        fi
        success "Vim dry-run complete"
        return 0
    fi

    deploy_vimrc
    install_plugins_and_coc "$skip_coc"
    print_done
}

if [[ "${SETUP_NO_MAIN:-false}" != "true" && "${SETUP_NO_MAIN:-false}" != "1" ]]; then
    main "$@"
fi
