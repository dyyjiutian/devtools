#!/usr/bin/env bash
#
# 轻量级 Zsh 插件安装配置脚本
# 替代 oh-my-zsh，安装以下工具并写入 ~/.zshrc 配置块:
#   - zsh-autosuggestions    命令历史自动建议
#   - zsh-syntax-highlighting 命令实时语法高亮
#   - zoxide                  智能目录跳转（替代 z/autojump）
#   - fzf                     模糊搜索（历史命令/文件/目录）
#   - starship                跨 shell 提示符（含 git 状态）
#

set -euo pipefail

ZSHRC="$HOME/.zshrc"
CONFIG_MARKER="# === Lightweight Zsh Plugins (devtools) ==="
CONFIG_MARKER_END="# === End Lightweight Zsh Plugins ==="
LINUX_PLUGIN_DIR="$HOME/.zsh"
STARSHIP_CONFIG_DIR="$HOME/.config"
STARSHIP_CONFIG="$STARSHIP_CONFIG_DIR/starship.toml"

info()    { echo -e "\033[34m[INFO]\033[0m $1"; }
success() { echo -e "\033[32m[OK]\033[0m $1"; }
warn()    { echo -e "\033[33m[WARN]\033[0m $1"; }
error()   { echo -e "\033[31m[ERROR]\033[0m $1"; }
step()    { echo -e "\033[36m[STEP]\033[0m $1"; }

DRY_RUN=false

show_help() {
    cat << 'EOF'
用法: ./setup.sh [选项]

轻量级 Zsh 插件安装配置脚本 (替代 oh-my-zsh)

安装内容:
    zsh-autosuggestions      命令历史自动建议（灰色提示）
    zsh-syntax-highlighting  命令实时语法高亮
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
    Tab             触发 zsh-autosuggestions 补全建议

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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- macOS: 通过 Homebrew 安装 ----
install_macos() {
    if ! command -v brew &>/dev/null; then
        error "Homebrew 未安装，请先安装: https://brew.sh"
        exit 1
    fi

    local tools=(zsh-autosuggestions zsh-syntax-highlighting zoxide fzf starship)
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

    _install_linux_plugin "zsh-autosuggestions" \
        "https://github.com/zsh-users/zsh-autosuggestions.git"

    _install_linux_plugin "zsh-syntax-highlighting" \
        "https://github.com/zsh-users/zsh-syntax-highlighting.git"

    _install_linux_zoxide
    _install_linux_fzf
    _install_linux_starship
}

_install_linux_plugin() {
    local name="$1"
    local repo="$2"
    local dir="$LINUX_PLUGIN_DIR/$name"

    if [[ -d "$dir" ]]; then
        success "$name 已安装，跳过"
        return
    fi

    if [[ "$DRY_RUN" == "false" ]]; then
        info "克隆 $name ..."
        git clone --depth=1 "$repo" "$dir"
        success "$name 安装完成"
    else
        info "[试运行] git clone $repo -> $dir"
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
        # --no-update-rc: 不自动修改 .zshrc/.bashrc，由本脚本统一管理
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

# ---- 生成 .zshrc 配置块 ----
generate_zshrc_config() {
    echo "$CONFIG_MARKER"
    echo ""
    echo "# Tab 补全"
    echo "autoload -Uz compinit && compinit"
    echo ""

    if [[ "$OS" == "Darwin" ]]; then
        local brew_prefix
        brew_prefix="$(brew --prefix)"
        echo "# zsh-autosuggestions"
        echo "source ${brew_prefix}/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
        echo ""
        echo "# zsh-syntax-highlighting (必须最后 source)"
        echo "source ${brew_prefix}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
        echo ""
        echo "# zoxide (z <关键词> 跳转，zi 交互式选择)"
        echo 'eval "$(zoxide init zsh)"'
        echo ""
        echo "# fzf (Ctrl+R 历史搜索，Ctrl+T 文件搜索，Alt+C 目录跳转)"
        echo 'eval "$(fzf --zsh)"'
    else
        echo "# zsh-autosuggestions"
        echo '[[ -f ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \'
        echo '    source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh'
        echo ""
        echo "# zsh-syntax-highlighting (必须最后 source)"
        echo '[[ -f ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \'
        echo '    source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'
        echo ""
        echo "# zoxide"
        echo 'command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"'
        echo ""
        echo "# fzf"
        echo '[[ -f ~/.fzf.zsh ]] && source ~/.fzf.zsh'
    fi

    echo ""
    echo "# starship prompt"
    echo 'eval "$(starship init zsh)"'
    echo ""
    echo "$CONFIG_MARKER_END"
}

# ---- 写入 .zshrc ----
configure_zshrc() {
    step "配置 ~/.zshrc ..."

    if [[ ! -f "$ZSHRC" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            touch "$ZSHRC"
            info "已创建 $ZSHRC"
        else
            info "[试运行] 将要创建 $ZSHRC"
        fi
    fi

    if grep -q "$CONFIG_MARKER" "$ZSHRC" 2>/dev/null; then
        warn "配置块已存在于 $ZSHRC，跳过写入"
        warn "如需重新生成，请删除 '$CONFIG_MARKER' 到 '$CONFIG_MARKER_END' 之间的内容后重新运行"
        return 0
    fi

    if [[ "$DRY_RUN" == "false" ]]; then
        local backup="${ZSHRC}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$ZSHRC" "$backup"
        success "已备份 ~/.zshrc -> $backup"

        printf '\n' >> "$ZSHRC"
        generate_zshrc_config >> "$ZSHRC"
        success "已将配置块写入 $ZSHRC"
    else
        info "[试运行] 将要追加以下配置块到 $ZSHRC:"
        echo "---"
        generate_zshrc_config
        echo "---"
    fi
}

# ---- 主流程 ----
main() {
    info "轻量级 Zsh 插件安装脚本"
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
    configure_zshrc

    echo ""
    configure_starship_config

    echo ""
    success "安装完成！"
    echo ""
    echo "  后续操作:"
    echo "  1. 运行 'source ~/.zshrc' 或重新打开终端以应用配置"
    echo "  2. Starship 已默认初始化为 tokyo 样式"
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

    if grep -qi "oh-my-zsh" "$ZSHRC" 2>/dev/null; then
        echo ""
        warn "检测到 ~/.zshrc 中存在 oh-my-zsh 配置"
        warn "如需完全替代，请手动注释或删除 ~/.zshrc 中的 oh-my-zsh 相关行"
        warn "建议保留备份后再操作"
    fi
}

main
