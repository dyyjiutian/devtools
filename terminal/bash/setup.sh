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

info()    { echo -e "\033[34m[INFO]\033[0m $1"; }
success() { echo -e "\033[32m[OK]\033[0m $1"; }
warn()    { echo -e "\033[33m[WARN]\033[0m $1"; }
error()   { echo -e "\033[31m[ERROR]\033[0m $1"; }
step()    { echo -e "\033[36m[STEP]\033[0m $1"; }

DRY_RUN=false

show_help() {
    cat << 'EOF'
用法: ./setup.sh [选项]

轻量级 Bash 插件安装配置脚本

安装内容:
    ble.sh                   命令历史自动建议 + 实时语法高亮
    zoxide                   智能目录跳转（替代 z/autojump）
    fzf                      模糊搜索（历史命令、文件查找）
    starship                 跨 shell 提示符（含 git 分支/状态）

选项:
    -h, --help      显示此帮助信息并退出
    -d, --dry-run   试运行模式，只显示将要执行的操作，不实际修改

安装后常用快捷键:
    Ctrl+R          fzf 模糊搜索历史命令
    Ctrl+T          fzf 模糊查找当前目录文件
    Alt+C           fzf 模糊跳转子目录
    z <关键词>       zoxide 智能跳转到常用目录

示例:
    ./setup.sh           # 完整安装
    ./setup.sh --dry-run # 预览将要执行的操作
    ./setup.sh --help    # 显示帮助
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)    show_help; exit 0 ;;
        -d|--dry-run) DRY_RUN=true; shift ;;
        *) error "未知选项: $1"; show_help; exit 1 ;;
    esac
done

OS="$(uname -s)"

# ---- macOS: 通过 Homebrew 安装 ----
install_macos() {
    if ! command -v brew &>/dev/null; then
        error "Homebrew 未安装，请先安装: https://brew.sh"
        exit 1
    fi

    local tools=(blesh fzf zoxide starship)
    for tool in "${tools[@]}"; do
        if brew list "$tool" &>/dev/null 2>&1; then
            success "$tool 已安装，跳过"
        else
            if [[ "$DRY_RUN" == "false" ]]; then
                info "安装 $tool ..."
                brew install "$tool"
                success "$tool 安装完成"
            else
                info "[试运行] brew install $tool"
            fi
        fi
    done
}

# ---- Linux: 从 git/curl 安装 ----
install_linux() {
    if ! command -v git &>/dev/null; then
        error "需要 git，请先安装"
        exit 1
    fi
    if ! command -v curl &>/dev/null; then
        error "需要 curl，请先安装"
        exit 1
    fi

    mkdir -p "$LINUX_PLUGIN_DIR"

    _install_linux_blesh
    _install_linux_zoxide
    _install_linux_fzf
    _install_linux_starship
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
    if [[ "$DRY_RUN" == "false" ]]; then
        info "安装 zoxide ..."
        curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
        success "zoxide 安装完成"
    else
        info "[试运行] curl install zoxide"
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
        git clone --depth 1 https://github.com/junegunn/fzf.git "$fzf_dir"
        # --no-update-rc: 不自动修改 .bashrc，由本脚本统一管理
        "$fzf_dir/install" --all --no-update-rc
        success "fzf 安装完成"
    else
        info "[试运行] git clone fzf -> $fzf_dir"
    fi
}

_install_linux_starship() {
    if command -v starship &>/dev/null; then
        success "starship 已安装，跳过"
        return
    fi
    if [[ "$DRY_RUN" == "false" ]]; then
        info "安装 starship ..."
        curl -sS https://starship.rs/install.sh | sh -s -- --yes
        success "starship 安装完成"
    else
        info "[试运行] curl install starship"
    fi
}

# ---- 生成 .bashrc 配置块 ----
# ble.sh 需要在其他插件前 source（--noattach），并在末尾 ble-attach。
generate_bashrc_config() {
    echo "$CONFIG_MARKER"
    echo ""

    if [[ "$OS" == "Darwin" ]]; then
        local brew_prefix
        brew_prefix="$(brew --prefix)"

        echo "# ble.sh (自动建议 + 语法高亮，需在其他插件之前 source)"
        echo "[[ \$- == *i* && -f \"${brew_prefix}/share/blesh/ble.sh\" ]] && \\"
        echo "    source \"${brew_prefix}/share/blesh/ble.sh\" --noattach"
        echo ""
        echo "# zoxide (z <关键词> 跳转，zi 交互式选择)"
        echo 'eval "$(zoxide init bash)"'
        echo ""
        echo "# fzf (Ctrl+R 历史搜索，Ctrl+T 文件搜索，Alt+C 目录跳转)"
        echo 'eval "$(fzf --bash)"'
        echo ""
        echo "# starship prompt"
        echo 'eval "$(starship init bash)"'
        echo ""
        echo "# ble.sh attach (必须在所有插件加载后)"
        echo '[[ ${BLE_VERSION-} ]] && ble-attach'
    else
        echo "# ble.sh (自动建议 + 语法高亮，需在其他插件之前 source)"
        echo '[[ $- == *i* && -f ~/.local/share/blesh/ble.sh ]] && \'
        echo '    source ~/.local/share/blesh/ble.sh --noattach'
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
        warn "配置块已存在于 $BASHRC，跳过写入"
        warn "如需重新生成，请删除 '$CONFIG_MARKER' 到 '$CONFIG_MARKER_END' 之间的内容后重新运行"
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

# ---- 主流程 ----
main() {
    info "轻量级 Bash 插件安装脚本"
    info "运行模式: $([[ "$DRY_RUN" == "true" ]] && echo "试运行" || echo "实际执行")"
    info "操作系统: $OS"
    echo ""

    step "安装插件..."
    case "$OS" in
        Darwin) install_macos ;;
        Linux)  install_linux ;;
        *) error "不支持的操作系统: $OS"; exit 1 ;;
    esac

    echo ""
    configure_bashrc

    echo ""
    success "安装完成！"
    echo ""
    echo "  后续操作:"
    echo "  1. 运行 'source ~/.bashrc' 或重新打开终端以应用配置"
    echo "  2. 运行 'starship preset' 选择提示符样式（可选）"
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

main
