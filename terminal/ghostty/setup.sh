#!/usr/bin/env bash
#
# Ghostty + Starship 配置安装脚本
# 用于安装 Ghostty 终端、Starship 提示符并应用自定义配置
#

set -euo pipefail

# 仅支持 macOS
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "错误: 此脚本仅支持 macOS（当前系统: $(uname -s)）" >&2
    exit 1
fi

# 配置路径
GHOSTTY_CONFIG_DIR="${GHOSTTY_CONFIG_DIR:-$HOME/Library/Application Support/com.mitchellh.ghostty}"
STARSHIP_CONFIG="${STARSHIP_CONFIG:-$HOME/.config/starship.toml}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 日志函数
log() {
    echo "[$(date +%H:%M:%S)] $*"
}

# 显示帮助信息
show_help() {
    cat << 'EOF'
用法: ./setup.sh [选项]

Ghostty + Starship 配置安装脚本

选项:
    -h, --help          显示此帮助信息并退出
    -d, --dry-run       试运行模式，只显示将要执行的修改
    --skip-starship     跳过 Starship 安装
    --skip-ghostty      跳过 Ghostty 安装
    --skip-fonts        跳过字体安装
    --uninstall         卸载配置，恢复默认

功能:
    1. 安装 Ghostty 终端 (通过 Homebrew Cask)
    2. 安装 Starship 提示符
    3. 安装 Nerd Font (JetBrainsMono Nerd Font)
    4. 应用自定义 Starship 配置 (starship.toml)
    5. 应用自定义 Ghostty 配置 (ghostty.config)
    6. 配置 Shell 集成 (zshrc/bashrc)

注意: 仅支持 macOS，需要预先安装 Homebrew。

示例:
    ./setup.sh              # 完整安装
    ./setup.sh --dry-run    # 试运行，查看将要做的修改
    ./setup.sh --skip-fonts # 跳过字体安装

文档:
    Ghostty: https://ghostty.org/docs
    Starship: https://starship.rs
EOF
}

# 解析命令行参数
DRY_RUN=false
SKIP_STARSHIP=false
SKIP_GHOSTTY=false
SKIP_FONTS=false
UNINSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-starship)
            SKIP_STARSHIP=true
            shift
            ;;
        --skip-ghostty)
            SKIP_GHOSTTY=true
            shift
            ;;
        --skip-fonts)
            SKIP_FONTS=true
            shift
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        *)
            echo "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

OS_TYPE="macos"
PKG_MANAGER=$(command -v brew &>/dev/null && echo "brew" || echo "none")

# 检查 Homebrew
check_homebrew() {
    if [[ "$PKG_MANAGER" != "brew" ]]; then
        log "⚠ Homebrew 未安装"
        log "  请先安装 Homebrew: https://brew.sh"
        if [[ "$OS_TYPE" == "macos" ]]; then
            log "  安装命令:"
            log '    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        fi
        return 1
    fi
    log "✓ Homebrew 已安装"
    return 0
}

# 安装 Ghostty
install_ghostty() {
    if [[ "$SKIP_GHOSTTY" == "true" ]]; then
        log "跳过 Ghostty 安装"
        return 0
    fi

    log "检查 Ghostty..."

    if command -v ghostty &>/dev/null || [[ -d "/Applications/Ghostty.app" ]]; then
        local ver
        ver=$(ghostty --version 2>/dev/null | head -1 || echo "(版本未知)")
        log "✓ Ghostty 已安装: $ver"
        return 0
    fi

    log "安装 Ghostty..."

    if ! check_homebrew; then
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[试运行] 将要执行: brew install --cask ghostty"
    else
        brew install --cask ghostty
        log "✓ Ghostty 安装完成"
    fi
}

# 安装 Starship
install_starship() {
    if [[ "$SKIP_STARSHIP" == "true" ]]; then
        log "跳过 Starship 安装"
        return 0
    fi

    log "检查 Starship..."

    if command -v starship &> /dev/null; then
        log "✓ Starship 已安装: $(starship --version | head -1)"
        return 0
    fi

    log "安装 Starship..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[试运行] 将要执行: curl -sS https://starship.rs/install.sh | sh"
        return 0
    fi

    # 使用官方安装脚本
    curl -sS https://starship.rs/install.sh | sh -s -- -y
    log "✓ Starship 安装完成"
}

# 安装字体
install_fonts() {
    if [[ "$SKIP_FONTS" == "true" ]]; then
        log "跳过字体安装"
        return 0
    fi

    log "检查 Nerd Font..."

    if ! check_homebrew; then
        return 1
    fi

    local font_name="font-jetbrains-mono-nerd-font"

    if brew list --cask "$font_name" &> /dev/null; then
        log "✓ 字体 $font_name 已安装"
    else
        log "安装 $font_name..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[试运行] 将要执行: brew install --cask $font_name"
        else
            brew install --cask "$font_name"
            log "✓ 字体安装完成"
        fi
    fi
}

# 备份现有配置
backup_config() {
    local file="$1"
    if [[ -f "$file" || -d "$file" ]]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[试运行] 将要备份 $file 到 $backup"
        else
            cp -r "$file" "$backup"
            log "✓ 已备份到 $backup"
        fi
    fi
}

# 配置 Starship
configure_starship() {
    if [[ "$SKIP_STARSHIP" == "true" ]]; then
        return 0
    fi

    log "配置 Starship..."

    # 创建配置目录
    local config_dir
    config_dir="$(dirname "$STARSHIP_CONFIG")"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[试运行] 将要创建目录: $config_dir"
    else
        mkdir -p "$config_dir"
    fi

    # 复制配置
    local starship_source="${SCRIPT_DIR}/starship.toml"
    if [[ ! -f "$starship_source" ]]; then
        log "⚠ 未找到 Starship 配置文件: $starship_source"
        return 1
    fi

    # 内容相同则跳过，避免重复备份
    if [[ -f "$STARSHIP_CONFIG" ]] && diff -q "$starship_source" "$STARSHIP_CONFIG" &>/dev/null; then
        log "✓ Starship 配置无变化，跳过"
        return 0
    fi

    backup_config "$STARSHIP_CONFIG"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[试运行] 将要复制 $starship_source 到 $STARSHIP_CONFIG"
    else
        cp "$starship_source" "$STARSHIP_CONFIG"
        log "✓ Starship 配置已应用"
    fi

    # 配置环境变量
    configure_starship_env
}

# 配置 Starship 环境变量 (zshrc/bashrc)
configure_starship_env() {
    local shell_rc=""
    local shell_name=""

    if [[ -n "${ZSH_VERSION:-}" ]] || [[ -f "$HOME/.zshrc" ]]; then
        shell_rc="$HOME/.zshrc"
        shell_name="zsh"
    elif [[ -n "${BASH_VERSION:-}" ]] || [[ -f "$HOME/.bashrc" ]]; then
        shell_rc="$HOME/.bashrc"
        shell_name="bash"
    fi

    if [[ -z "$shell_rc" ]]; then
        log "⚠ 未检测到 shell 配置文件，请手动添加 Starship 初始化"
        return 1
    fi

    log "检测到 $shell_name，配置 $shell_rc..."

    # 检查是否已配置
    if grep -q "starship init" "$shell_rc" 2>/dev/null; then
        log "✓ Starship 已在 $shell_name 中配置"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[试运行] 将要添加 Starship 初始化到 $shell_rc"
        return 0
    fi

    # 添加 Starship 初始化
    {
        echo ""
        echo "# =========================================="
        echo "# Starship 提示符配置"
        echo "# =========================================="
        echo "eval \"\$(starship init ${shell_name})\""
    } >> "$shell_rc"

    log "✓ Starship 初始化已添加到 $shell_rc"
}

# 配置 Ghostty
configure_ghostty() {
    if [[ "$SKIP_GHOSTTY" == "true" ]]; then
        return 0
    fi

    log "配置 Ghostty..."

    # 创建配置目录
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[试运行] 将要创建目录: $GHOSTTY_CONFIG_DIR"
    else
        mkdir -p "$GHOSTTY_CONFIG_DIR"
    fi

    # 复制配置
    local ghostty_config="${GHOSTTY_CONFIG_DIR}/config"
    local ghostty_source="${SCRIPT_DIR}/ghostty.config"
    if [[ ! -f "$ghostty_source" ]]; then
        log "⚠ 未找到 Ghostty 配置文件: $ghostty_source"
        return 1
    fi

    # 内容相同则跳过，避免重复备份
    if [[ -f "$ghostty_config" ]] && diff -q "$ghostty_source" "$ghostty_config" &>/dev/null; then
        log "✓ Ghostty 配置无变化，跳过"
        return 0
    fi

    backup_config "$ghostty_config"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[试运行] 将要复制 $ghostty_source 到 $ghostty_config"
    else
        cp "$ghostty_source" "$ghostty_config"
        log "✓ Ghostty 配置已应用"
    fi
}

# 卸载配置
uninstall() {
    log "卸载 Ghostty + Starship 配置..."

    # 恢复 Starship 配置
    if [[ -f "$STARSHIP_CONFIG" ]]; then
        local starship_backup
        starship_backup=$(find "$(dirname "$STARSHIP_CONFIG")" -name "starship.toml.backup.*" -type f 2>/dev/null | sort -r | head -1)
        if [[ -n "$starship_backup" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log "[试运行] 将要恢复 Starship 配置: $starship_backup"
            else
                cp "$starship_backup" "$STARSHIP_CONFIG"
                log "✓ Starship 配置已恢复"
            fi
        else
            if [[ "$DRY_RUN" == "true" ]]; then
                log "[试运行] 将要删除 Starship 配置"
            else
                rm -f "$STARSHIP_CONFIG"
                log "✓ Starship 配置已删除"
            fi
        fi
    fi

    # 恢复 Ghostty 配置
    local ghostty_config="${GHOSTTY_CONFIG_DIR}/config"
    if [[ -f "$ghostty_config" ]]; then
        local ghostty_backup
        ghostty_backup=$(find "$GHOSTTY_CONFIG_DIR" -name "config.backup.*" -type f 2>/dev/null | sort -r | head -1)
        if [[ -n "$ghostty_backup" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log "[试运行] 将要恢复 Ghostty 配置: $ghostty_backup"
            else
                cp "$ghostty_backup" "$ghostty_config"
                log "✓ Ghostty 配置已恢复"
            fi
        else
            if [[ "$DRY_RUN" == "true" ]]; then
                log "[试运行] 将要删除 Ghostty 配置"
            else
                rm -f "$ghostty_config"
                log "✓ Ghostty 配置已删除"
            fi
        fi
    fi

    # 从 shell rc 中移除 Starship 初始化
    local shell_rc=""
    if [[ -f "$HOME/.zshrc" ]]; then
        shell_rc="$HOME/.zshrc"
    elif [[ -f "$HOME/.bashrc" ]]; then
        shell_rc="$HOME/.bashrc"
    fi

    if [[ -n "$shell_rc" ]] && [[ "$DRY_RUN" == "false" ]]; then
        # 移除 Starship 相关行
        if grep -q "Starship 提示符配置" "$shell_rc" 2>/dev/null; then
            local temp_file
            temp_file=$(mktemp)

            # awk 状态机：逐行匹配，遇到块开头标记则进入跳过模式
            # 注意：不能在单行 awk 正则中用 \n 匹配换行，必须用状态变量
            awk '
                /^# Starship 提示符配置$/ { in_block=1; next }
                in_block && /^eval.*starship init/ { in_block=0; next }
                in_block { next }
                /^# =+$/ && saw_sep { saw_sep=0; next }
                /^# =+$/ { saw_sep=1; hold=$0; next }
                saw_sep { print hold; saw_sep=0 }
                { print }
            ' "$shell_rc" > "$temp_file"

            mv "$temp_file" "$shell_rc"
            log "✓ 已从 $shell_rc 移除 Starship 配置"
        fi
    fi

    log "卸载完成"
}

# 显示配置摘要
show_summary() {
    echo
    echo "=========================================="
    echo "    Ghostty + Starship 配置安装完成"
    echo "=========================================="
    echo
    echo "已完成的操作:"
    echo "  • Ghostty 终端: $([[ "$SKIP_GHOSTTY" == "true" ]] && echo "跳过" || echo "已配置")"
    echo "  • Starship 提示符: $([[ "$SKIP_STARSHIP" == "true" ]] && echo "跳过" || echo "已配置")"
    echo "  • Nerd Font: $([[ "$SKIP_FONTS" == "true" ]] && echo "跳过" || echo "已安装")"
    echo
    echo "配置文件位置:"
    echo "  • Starship: $STARSHIP_CONFIG"
    echo "  • Ghostty:  $GHOSTTY_CONFIG_DIR/config"
    echo
    echo "下一步:"
    echo "  1. 重新打开终端或运行: source ~/.zshrc (或 ~/.bashrc)"
    echo "  2. 启动 Ghostty: 按 Cmd+Space 搜索 Ghostty"
    echo "  3. 在 Ghostty 设置中检查字体是否设置为 JetBrainsMono Nerd Font"
    echo
    echo "常用命令:"
    echo "  • starship config    # 编辑 Starship 配置"
    echo "  • starship preset    # 查看预设主题"
    echo "  • ghostty +show-config  # 查看当前 Ghostty 配置"
    echo "  • ghostty +list-themes  # 列出可用主题"
    echo
    echo "文档链接:"
    echo "  • Ghostty: https://ghostty.org/docs"
    echo "  • Starship: https://starship.rs/config"
    echo "=========================================="
}

# 主函数
main() {
    echo
    log "Ghostty + Starship 配置安装脚本"
    log "操作系统: $OS_TYPE"
    log "包管理器: $PKG_MANAGER"
    log "运行模式: $([[ "$DRY_RUN" == "true" ]] && echo "试运行" || echo "实际执行")"
    echo

    if [[ "$UNINSTALL" == "true" ]]; then
        uninstall
        exit 0
    fi

    # 执行安装步骤
    install_ghostty
    install_starship
    install_fonts
    configure_starship
    configure_ghostty

    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        log "试运行完成！实际执行时不会进行任何修改。"
    else
        show_summary
    fi
}

main
