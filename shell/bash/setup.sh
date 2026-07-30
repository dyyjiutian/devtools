#!/usr/bin/env bash
#
# 轻量级 Bash 插件安装配置脚本
# 安装以下工具并写入 ~/.bashrc 配置块:
#   - ble.sh             命令历史自动建议 + 实时语法高亮
#   - zoxide             智能目录跳转（替代 z/autojump）
#   - fzf                模糊搜索（历史命令/文件/目录）
#   - starship           跨 shell 提示符（含 git 状态）
#

set -euo pipefail

BASHRC="$HOME/.bashrc"
CONFIG_MARKER="# === Lightweight Bash Plugins (devtools) ==="
CONFIG_MARKER_END="# === End Lightweight Bash Plugins ==="
LINUX_PLUGIN_DIR="$HOME/.bash"
LOCAL_BIN_DIR="$HOME/.local/bin"
STARSHIP_CONFIG_DIR="$HOME/.config"
STARSHIP_CONFIG="$STARSHIP_CONFIG_DIR/starship.toml"

# 本地缓存目录：在线下载失败时回退到 cache/binaries 中的预下载文件
# 运行 `bash cache/download.sh linux` 可预先下载所有文件
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${DEVTOOLS_CACHE_DIR:-${SCRIPT_DIR}/../../cache}"

info()    { echo -e "\033[34m[INFO]\033[0m $1"; }
success() { echo -e "\033[32m[OK]\033[0m $1"; }
warn()    { echo -e "\033[33m[WARN]\033[0m $1"; }
error()   { echo -e "\033[31m[ERROR]\033[0m $1"; }
step()    { echo -e "\033[36m[STEP]\033[0m $1"; }

DRY_RUN=false
COMMAND=""
SELECTED_PLUGINS=()
PLUGIN_IDS=(blesh zoxide fzf starship)

plugin_description() {
    case "$1" in
        blesh)    echo "命令历史自动建议 + 实时语法高亮" ;;
        zoxide)   echo "智能目录跳转" ;;
        fzf)      echo "模糊搜索" ;;
        starship) echo "跨 shell 提示符" ;;
        *) return 1 ;;
    esac
}

normalize_plugin_id() {
    case "$1" in
        ble.sh|blesh) echo "blesh" ;;
        zoxide|fzf|starship) echo "$1" ;;
        *) return 1 ;;
    esac
}

plugin_is_installed() {
    case "$1" in
        blesh)
            if [[ "$OS" == "Darwin" ]]; then
                local brew_prefix
                brew_prefix="$(brew --prefix 2>/dev/null || true)"
                [[ -n "$brew_prefix" && -f "${brew_prefix}/share/blesh/ble.sh" ]]
            else
                [[ -f "$HOME/.local/share/blesh/ble.sh" ]]
            fi
            ;;
        zoxide)   command -v zoxide &>/dev/null ;;
        fzf)      command -v fzf &>/dev/null ;;
        starship) command -v starship &>/dev/null ;;
        *) return 1 ;;
    esac
}

cmd_list() {
    local id desc status
    for id in "${PLUGIN_IDS[@]}"; do
        desc="$(plugin_description "$id")"
        if plugin_is_installed "$id"; then
            status="[installed]"
        else
            status="[missing]"
        fi
        printf '%-10s %-36s %s\n' "$id" "$desc" "$status"
    done
}

show_help() {
    cat << 'EOF'
用法: ./setup.sh [子命令] [选项] [插件...]

轻量级 Bash 插件安装配置脚本

子命令:
    install             安装插件（默认子命令）
    list                列出插件及安装状态

插件:
    blesh (ble.sh)      命令历史自动建议 + 实时语法高亮
    zoxide              智能目录跳转（替代 z/autojump）
    fzf                 模糊搜索（历史命令、文件查找）
    starship            跨 shell 提示符（含 git 分支/状态）

选项:
    -h, --help          显示此帮助信息并退出
    -n, --dry-run       试运行模式，只显示将要执行的操作，不实际修改

安装后常用快捷键:
    Ctrl+R          fzf 模糊搜索历史命令
    Ctrl+T          fzf 模糊查找当前目录文件
    Alt+C           fzf 模糊跳转子目录
    z <关键词>       zoxide 智能跳转到常用目录

示例:
    ./setup.sh                  # 完整安装
    ./setup.sh install          # 完整安装
    ./setup.sh list             # 查看插件安装状态
    ./setup.sh install -n       # 预览将要执行的操作
    ./setup.sh --help           # 显示帮助
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            install|list)
                if [[ -n "$COMMAND" ]]; then
                    error "重复子命令: $1"
                    exit 1
                fi
                COMMAND="$1"
                shift
                ;;
            -*)
                error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$COMMAND" || "$COMMAND" == "install" ]]; then
                    COMMAND="${COMMAND:-install}"
                    local pid
                    pid="$(normalize_plugin_id "$1")" || {
                        error "未知插件: $1（运行: $(basename "$0") list）"
                        exit 1
                    }
                    SELECTED_PLUGINS+=("$pid")
                    shift
                else
                    error "list 不接受额外参数: $1"
                    exit 1
                fi
                ;;
        esac
    done

    COMMAND="${COMMAND:-install}"
}

parse_args "$@"

OS="$(uname -s)"

# ---- macOS: 通过 Homebrew 安装 ----
_install_macos_plugin() {
    local brew_name="$1"
    if brew list "$brew_name" &>/dev/null 2>&1; then
        success "$brew_name 已安装，跳过"
        return
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[试运行] brew install $brew_name"
        return
    fi
    info "安装 $brew_name ..."
    brew install "$brew_name"
    success "$brew_name 安装完成"
}

_install_linux_blesh() {
    local install_dir="$HOME/.local/share/blesh"
    if [[ -f "$install_dir/ble.sh" ]]; then
        success "ble.sh 已安装，跳过"
        return
    fi
    if ! command -v make &>/dev/null; then
        warn "ble.sh 需要 make，请先安装 build tools 后重新运行"
        warn "  Ubuntu/Debian: sudo apt-get install build-essential"
        warn "  CentOS/RHEL:   sudo yum groupinstall 'Development Tools'"
        return
    fi
    local src_dir="$LINUX_PLUGIN_DIR/ble.sh"
    if [[ "$DRY_RUN" == "false" ]]; then
        info "克隆并编译 ble.sh ..."
        git clone --recursive --depth 1 --shallow-submodules \
            https://github.com/akinomyoga/ble.sh.git "$src_dir"
        make -C "$src_dir" install PREFIX="$HOME/.local"
        success "ble.sh 安装完成 -> $install_dir/ble.sh"
    else
        info "[试运行] git clone ble.sh -> $src_dir && make install PREFIX=~/.local"
    fi
}

_install_linux_zoxide() {
    if command -v zoxide &>/dev/null; then
        success "zoxide 已安装，跳过"
        return
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[试运行] curl install zoxide（失败时回退本地缓存）"
        return
    fi

    info "安装 zoxide ..."
    # 优先官方脚本在线安装；中国等网络受限环境可能失败，失败时回退本地缓存
    if curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh; then
        success "zoxide 安装完成"
        return
    fi

    warn "zoxide 在线安装失败，尝试使用本地缓存安装 ..."
    # 缓存也失败时不中断整个脚本，继续安装其余插件
    _install_linux_zoxide_from_cache || warn "zoxide 安装失败，已跳过，可稍后手动安装"
}

# 从 cache/binaries 中的预下载二进制包安装 zoxide（离线回退）
_install_linux_zoxide_from_cache() {
    local version="0.9.4" arch filename cached tmpdir bindir
    case "$(uname -m)" in
        aarch64|arm64) arch="aarch64-unknown-linux-musl" ;;
        *)             arch="x86_64-unknown-linux-musl" ;;
    esac
    filename="zoxide-${version}-${arch}.tar.gz"
    cached="${CACHE_DIR}/binaries/${filename}"

    if [[ ! -f "$cached" ]]; then
        error "本地缓存不存在: ${cached}"
        error "请联网运行 'bash cache/download.sh linux' 预先下载，或手动安装 zoxide"
        return 1
    fi

    info "使用本地缓存: binaries/${filename}"
    bindir="$HOME/.local/bin"
    mkdir -p "$bindir"
    tmpdir=$(mktemp -d)
    if tar -xzf "$cached" -C "$tmpdir" zoxide 2>/dev/null; then
        mv "$tmpdir/zoxide" "$bindir/zoxide"
        chmod +x "$bindir/zoxide"
        rm -rf "$tmpdir"
        success "zoxide 安装完成 -> $bindir/zoxide"
        if [[ ":$PATH:" != *":$bindir:"* ]]; then
            warn "$bindir 不在 PATH 中，请确保已将其加入 PATH 后重新打开终端"
        fi
    else
        rm -rf "$tmpdir"
        error "解压 zoxide 缓存失败: ${cached}"
        return 1
    fi
}

_install_linux_fzf() {
    if command -v fzf &>/dev/null; then
        success "fzf 已安装，跳过"
        return
    fi
    local fzf_dir="$HOME/.fzf"
    if [[ "$DRY_RUN" == "false" ]]; then
        info "安装 fzf ..."
        if [[ -f "$fzf_dir/install" ]]; then
            info "发现已有 fzf 源码目录，复用安装脚本 ..."
            bash "$fzf_dir/install" --all --no-update-rc
            success "fzf 安装完成"
            return
        fi
        if [[ -d "$fzf_dir" ]]; then
            local backup_dir="${fzf_dir}.backup.$(date +%Y%m%d_%H%M%S).$$"
            mv "$fzf_dir" "$backup_dir"
            warn "发现不完整的 fzf 目录，已备份到: $backup_dir"
        fi
        git clone --depth 1 https://github.com/junegunn/fzf.git "$fzf_dir"
        # --no-update-rc: 不自动修改 .bashrc，由本脚本统一管理
        "$fzf_dir/install" --all --no-update-rc
        success "fzf 安装完成"
    else
        info "[试运行] git clone fzf -> $fzf_dir"
    fi
}

_starship_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "x86_64-unknown-linux-musl" ;;
        aarch64|arm64) echo "aarch64-unknown-linux-musl" ;;
        *)
            error "Starship 不支持当前架构: $(uname -m)"
            return 1
            ;;
    esac
}

_install_linux_starship_from_cache() {
    local arch filename cached tmpdir
    arch="$(_starship_arch)" || return 1
    filename="starship-${arch}.tar.gz"
    cached="${CACHE_DIR}/binaries/${filename}"

    if [[ ! -f "$cached" ]]; then
        return 2
    fi

    info "使用本地缓存: binaries/${filename}"
    tmpdir=$(mktemp -d)
    if ! tar -xzf "$cached" -C "$tmpdir" starship 2>/dev/null || [[ ! -x "$tmpdir/starship" ]]; then
        rm -rf "$tmpdir"
        error "解压 Starship 缓存失败或文件不可执行: ${cached}"
        return 1
    fi

    mv "$tmpdir/starship" "$LOCAL_BIN_DIR/starship"
    chmod +x "$LOCAL_BIN_DIR/starship"
    rm -rf "$tmpdir"
    success "starship 安装完成 -> $LOCAL_BIN_DIR/starship"
    if [[ ":$PATH:" != *":$LOCAL_BIN_DIR:"* ]]; then
        warn "$LOCAL_BIN_DIR 不在当前 PATH 中，重新打开终端或 source ~/.bashrc 后生效"
    fi
}

_install_linux_starship() {
    if command -v starship &>/dev/null; then
        success "starship 已安装，跳过"
        return
    fi
    if [[ "$DRY_RUN" == "false" ]]; then
        local cache_status
        if _install_linux_starship_from_cache; then
            return
        else
            cache_status=$?
        fi
        if [[ "$cache_status" -eq 1 ]]; then
            return 1
        fi

        warn "Starship 本地缓存不存在，尝试在线安装 ..."
        info "安装 starship ..."
        curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$LOCAL_BIN_DIR"
        if [[ -x "$LOCAL_BIN_DIR/starship" ]]; then
            success "starship 安装完成 -> $LOCAL_BIN_DIR/starship"
            if [[ ":$PATH:" != *":$LOCAL_BIN_DIR:"* ]]; then
                warn "$LOCAL_BIN_DIR 不在当前 PATH 中，重新打开终端或 source ~/.bashrc 后生效"
            fi
        else
            error "starship 安装后未找到可执行文件: $LOCAL_BIN_DIR/starship"
            return 1
        fi
    else
        info "[试运行] curl install starship -> $LOCAL_BIN_DIR"
    fi
}

# ---- 初始化 Starship 配置 ----
configure_starship_config() {
    step "配置 Starship prompt ..."

    local source_config
    if [[ "$OS" == "Darwin" ]]; then
        source_config="${SCRIPT_DIR}/../starship/starship-tokyo.toml"
    else
        source_config="${SCRIPT_DIR}/../starship/starship-tokyo-linux.toml"
    fi

    if [[ ! -f "$source_config" ]]; then
        error "未找到 Starship 配置模板: $source_config"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[试运行] 将复制 $source_config 到 $STARSHIP_CONFIG"
        return
    fi

    mkdir -p "$STARSHIP_CONFIG_DIR"
    if [[ -f "$STARSHIP_CONFIG" ]]; then
        local backup="${STARSHIP_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$STARSHIP_CONFIG" "$backup"
        success "已备份 Starship 配置 -> $backup"
    fi

    cp "$source_config" "$STARSHIP_CONFIG"
    success "已写入 Starship 配置 -> $STARSHIP_CONFIG"
}

# ---- 生成 .bashrc 配置块 ----
# ble.sh 需要在其他插件前 source（--noattach），并在末尾 ble-attach。
# 同时用 --noinputrc 让 ble.sh 不重建 readline (~/.inputrc) 的键绑定,
# 避免个别环境里 inputrc 把普通方向键 (\eOD/\eOC) 误绑成按词移动。
generate_bashrc_config() {
    echo "$CONFIG_MARKER"
    echo ""

    if [[ "$OS" == "Darwin" ]]; then
        local brew_prefix
        brew_prefix="$(brew --prefix)"

        echo "# ble.sh (自动建议 + 语法高亮，需在其他插件之前 source)"
        echo "# --noinputrc: 不导入 readline 的 ~/.inputrc，避免其中的方向键绑定"
        echo "[[ \$- == *i* && -f \"${brew_prefix}/share/blesh/ble.sh\" ]] && \\"
        echo "    source \"${brew_prefix}/share/blesh/ble.sh\" --noattach --noinputrc"
        echo ""
        echo "# zoxide (z <关键词> 跳转，zi 交互式选择)"
        echo 'command -v zoxide &>/dev/null && eval "$(zoxide init bash)"'
        echo ""
        echo "# fzf (Ctrl+R 历史搜索，Ctrl+T 文件搜索，Alt+C 目录跳转)"
        echo 'command -v fzf &>/dev/null && eval "$(fzf --bash)"'
        echo ""
        echo "# starship prompt"
        echo 'command -v starship &>/dev/null && eval "$(starship init bash)"'
        echo ""
        echo "# ble.sh attach (必须在所有插件加载后)"
        echo '[[ ${BLE_VERSION-} ]] && ble-attach'
    else
        echo "# 用户级命令目录"
        echo '[[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"'
        echo ""
        echo "# ble.sh (自动建议 + 语法高亮，需在其他插件之前 source)"
        echo '[[ $- == *i* && -f ~/.local/share/blesh/ble.sh ]] && \'
        echo '    source ~/.local/share/blesh/ble.sh --noattach --noinputrc'
        echo ""
        echo "# zoxide"
        echo 'command -v zoxide &>/dev/null && eval "$(zoxide init bash)"'
        echo ""
        echo "# fzf"
        echo '[[ -f ~/.fzf.bash ]] && source ~/.fzf.bash'
        echo ""
        echo "# starship prompt"
        echo 'command -v starship &>/dev/null && eval "$(starship init bash)"'
        echo ""
        echo "# ble.sh attach (必须在所有插件加载后)"
        echo '[[ ${BLE_VERSION-} ]] && ble-attach'
    fi

    echo ""
    echo "$CONFIG_MARKER_END"
}

# ---- 写入 .bashrc ----
configure_bashrc() {
    step "配置 ~/.bashrc ..."

    if [[ ! -f "$BASHRC" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            touch "$BASHRC"
            info "已创建 $BASHRC"
        else
            info "[试运行] 将要创建 $BASHRC"
        fi
    fi

    if grep -q "$CONFIG_MARKER" "$BASHRC" 2>/dev/null; then
        warn "配置块已存在于 $BASHRC，将替换为最新配置"
        if [[ "$DRY_RUN" == "false" ]]; then
            local backup="${BASHRC}.backup.$(date +%Y%m%d_%H%M%S)"
            local tmp
            tmp="$(mktemp)"
            cp "$BASHRC" "$backup"
            awk -v start="$CONFIG_MARKER" -v end="$CONFIG_MARKER_END" '
                $0 == start { in_block = 1; next }
                $0 == end { in_block = 0; next }
                !in_block { print }
            ' "$BASHRC" > "$tmp"
            printf '\n' >> "$tmp"
            generate_bashrc_config >> "$tmp"
            mv "$tmp" "$BASHRC"
            success "已备份 ~/.bashrc -> $backup"
            success "已更新 $BASHRC 中的配置块"
        else
            info "[试运行] 将替换 $BASHRC 中已有配置块为:"
            echo "---"
            generate_bashrc_config
            echo "---"
        fi
        return 0
    fi

    if [[ "$DRY_RUN" == "false" ]]; then
        local backup="${BASHRC}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$BASHRC" "$backup"
        success "已备份 ~/.bashrc -> $backup"

        printf '\n' >> "$BASHRC"
        generate_bashrc_config >> "$BASHRC"
        success "已将配置块写入 $BASHRC"
    else
        info "[试运行] 将要追加以下配置块到 $BASHRC:"
        echo "---"
        generate_bashrc_config
        echo "---"
    fi
}

# ---- 按插件安装 ----
install_plugin() {
    local id="$1"
    case "$OS" in
        Darwin)
            case "$id" in
                blesh)    _install_macos_plugin blesh ;;
                zoxide)   _install_macos_plugin zoxide ;;
                fzf)      _install_macos_plugin fzf ;;
                starship) _install_macos_plugin starship ;;
            esac
            ;;
        Linux)
            mkdir -p "$LINUX_PLUGIN_DIR" "$LOCAL_BIN_DIR"
            case "$id" in
                blesh)    _install_linux_blesh ;;
                zoxide)   _install_linux_zoxide ;;
                fzf)      _install_linux_fzf ;;
                starship) _install_linux_starship ;;
            esac
            ;;
        *) error "不支持的操作系统: $OS"; exit 1 ;;
    esac
}

cmd_install() {
    local plugins=("$@")
    local id want_starship_config=false
    if [[ ${#plugins[@]} -eq 0 ]]; then
        plugins=("${PLUGIN_IDS[@]}")
        want_starship_config=true
    else
        for id in "${plugins[@]}"; do
            [[ "$id" == "starship" ]] && want_starship_config=true
        done
    fi

    info "轻量级 Bash 插件安装脚本"
    info "运行模式: $([[ "$DRY_RUN" == "true" ]] && echo "试运行" || echo "实际执行")"
    info "操作系统: $OS"
    info "插件: ${plugins[*]}"
    echo ""

    if [[ "$OS" == "Darwin" ]] && ! command -v brew &>/dev/null; then
        error "Homebrew 未安装，请先安装: https://brew.sh"
        exit 1
    fi
    if [[ "$OS" == "Linux" ]]; then
        command -v git &>/dev/null || { error "需要 git，请先安装"; exit 1; }
        command -v curl &>/dev/null || { error "需要 curl，请先安装"; exit 1; }
    fi

    step "安装插件..."
    for id in "${plugins[@]}"; do
        install_plugin "$id"
    done

    echo ""
    configure_bashrc

    if [[ "$want_starship_config" == "true" ]]; then
        echo ""
        configure_starship_config
    fi

    echo ""
    success "安装完成！"
    echo ""
    echo "  后续操作:"
    echo "  1. 运行 'source ~/.bashrc' 或重新打开终端以应用配置"
    if [[ "$want_starship_config" == "true" ]]; then
        echo "  2. Starship 已默认初始化为 tokyo 样式"
    fi
    echo ""
    echo "  关于 zoxide (z 命令):"
    echo "  zoxide 需要先记录你访问过的目录，才能使用 'z' 跳转。"
    echo "  激活后用 'cd' 正常进入几个目录，之后即可用 'z <关键词>' 跳转。"
    echo "  例如: cd ~/projects/foo  →  之后任意位置输入 z foo 即可跳转"
    echo ""
    echo "  快捷键速查:"
    echo "  Ctrl+R     fzf 模糊搜索历史命令"
    echo "  Ctrl+T     fzf 模糊查找当前目录文件"
    echo "  Alt+C      fzf 模糊跳转子目录"
    echo "  z <名称>    zoxide 跳转常用目录（需先用 cd 访问过）"
    echo "  zi         zoxide 交互式目录选择（需要 fzf）"
    echo ""
}

case "$COMMAND" in
    list) cmd_list ;;
    install) cmd_install ${SELECTED_PLUGINS[@]+"${SELECTED_PLUGINS[@]}"} ;;
    *) error "未知命令: $COMMAND"; exit 1 ;;
esac
