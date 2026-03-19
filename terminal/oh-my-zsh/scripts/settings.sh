#!/usr/bin/env bash
#
# Oh My Zsh 配置脚本
# 用于自动配置 zsh 主题、插件和安装第三方插件
#

set -e

# Oh My Zsh 安装路径
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
ZSHRC="$HOME/.zshrc"

# 显示帮助信息
show_help() {
    cat << 'EOF'
用法: ./settings.sh [选项]

Oh My Zsh 自动配置脚本

选项:
    -h, --help      显示此帮助信息并退出
    -d, --dry-run   试运行模式，只显示将要执行的修改，不实际修改文件

功能:
    1. 检查并恢复 Oh My Zsh 安装前覆盖的 ~/.zshrc 配置
    2. 设置 zsh 主题为 agnoster
    3. 禁用 Oh My Zsh 自动更新
    4. 启用插件: git, z, web-search
    5. 安装第三方插件:
       - zsh-autosuggestions (命令自动建议)
       - zsh-syntax-highlighting (语法高亮)
    6. 通过 Homebrew 安装 Meslo LG Nerd Font (agnoster主题所需)

要求:
    - 已安装 Oh My Zsh
    - 已安装 git
    - 有写入 ~/.zshrc 的权限

示例:
    ./settings.sh           # 执行配置
    ./settings.sh --help    # 显示帮助
    ./settings.sh --dry-run # 试运行，查看将要做的修改

官方文档:
    https://ohmyz.sh/
    https://github.com/ohmyzsh/ohmyzsh/wiki
EOF
}

# 解析命令行参数
DRY_RUN=false

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
        *)
            echo "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 日志函数
log() {
    echo "[$(date +%H:%M:%S)] $*"
}

# 检查是否已安装 Oh My Zsh
check_ohmyzsh() {
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        echo "错误: Oh My Zsh 未安装"
        echo "请先安装 Oh My Zsh: https://ohmyz.sh/#install"
        exit 1
    fi
    log "✓ Oh My Zsh 已安装"
}

# 检查并恢复 oh-my-zsh 安装前的 .zshrc 配置
check_and_restore_pre_omz_config() {
    local pre_omz_file="$HOME/.zshrc.pre-oh-my-zsh"

    if [[ ! -f "$pre_omz_file" ]]; then
        return 0
    fi

    echo
    log "检测到 Oh My Zsh 安装时备份的原始配置文件:"
    log "  备份文件: $pre_omz_file"
    log "  当前文件: $ZSHRC"
    echo
    log "Oh My Zsh 安装时可能覆盖了您原有的 ~/.zshrc 配置"
    echo

    # 显示差异
    log "原有配置与当前配置的差异:"
    echo "---"
    # 使用 comm 比较两个文件的差异，只显示在 pre-omz 中存在但在当前不存在的行
    local diff_content
    diff_content=$(comm -23 <(sort "$pre_omz_file" 2>/dev/null | uniq) <(sort "$ZSHRC" 2>/dev/null | uniq) 2>/dev/null || true)

    if [[ -z "$diff_content" ]]; then
        log "原有配置与当前配置无差异，跳过恢复"
        return 0
    fi

    echo "$diff_content" | head -20
    local diff_lines
    diff_lines=$(echo "$diff_content" | wc -l | tr -d ' ')
    if [[ $diff_lines -gt 20 ]]; then
        log "... 还有 $((diff_lines - 20)) 行差异未显示"
    fi
    echo "---"
    echo

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[试运行] 检测到差异，实际运行时将询问是否恢复"
        return 0
    fi

    # 询问用户
    read -r -p "是否将原有配置中差异的部分追加到现有 ~/.zshrc 中? [y/N]: " response
    echo

    if [[ "$response" =~ ^[Yy]$ ]]; then
        local temp_file
        temp_file=$(mktemp)

        echo "" >> "$ZSHRC"
        echo "# ==========================================" >> "$ZSHRC"
        echo "# 从 ~/.zshrc.pre-oh-my-zsh 恢复的自定义配置" >> "$ZSHRC"
        echo "# 原配置备份于: $pre_omz_file" >> "$ZSHRC"
        echo "# ==========================================" >> "$ZSHRC"
        echo "" >> "$ZSHRC"
        echo "$diff_content" >> "$ZSHRC"

        log "✓ 已将原有配置差异部分追加到 ~/.zshrc"
        log "  追加了 $diff_lines 行配置"
        log "  建议查看 ~/.zshrc 确认配置是否正确"
    else
        log "已跳过恢复，原有配置保留在: $pre_omz_file"
    fi
    echo
}

# 备份 .zshrc
backup_zshrc() {
    if [[ -f "$ZSHRC" ]]; then
        local backup_file="${ZSHRC}.backup.$(date +%Y%m%d_%H%M%S)"
        if [[ "$DRY_RUN" == "false" ]]; then
            cp "$ZSHRC" "$backup_file"
            log "✓ 已备份 .zshrc 到 $backup_file"
        else
            log "[试运行] 将要备份 .zshrc 到 $backup_file"
        fi
    fi
}

# 设置主题为 agnoster
set_theme() {
    log "设置主题为 agnoster..."
    if [[ "$DRY_RUN" == "false" ]]; then
        sed -i '' 's/^ZSH_THEME=.*/ZSH_THEME="agnoster"/' "$ZSHRC"
        log "✓ 主题已设置为 agnoster"
    else
        log "[试运行] 将要设置 ZSH_THEME=\"agnoster\""
    fi
}

# 禁用自动更新
disable_auto_update() {
    log "禁用 Oh My Zsh 自动更新..."
    if [[ "$DRY_RUN" == "false" ]]; then
        # 检查是否已存在 DISABLE_AUTO_UPDATE 配置
        if grep -q "^DISABLE_AUTO_UPDATE=" "$ZSHRC"; then
            sed -i '' 's/^DISABLE_AUTO_UPDATE=.*/DISABLE_AUTO_UPDATE="true"/' "$ZSHRC"
        else
            # 在 ZSH_THEME 行之后添加
            sed -i '' '/^ZSH_THEME=/a\
# 禁用自动更新\
DISABLE_AUTO_UPDATE="true"' "$ZSHRC"
        fi
        log "✓ 已禁用自动更新"

        # 优化 git 目录下的命令响应速度
        if ! grep -q "^DISABLE_UNTRACKED_FILES_DIRTY=" "$ZSHRC"; then
            sed -i '' '/^DISABLE_AUTO_UPDATE=/a\
# 不检查未跟踪文件，加速 git 目录下的命令响应\
DISABLE_UNTRACKED_FILES_DIRTY="true"' "$ZSHRC"
        fi
        if ! grep -q "^DISABLE_AUTO_TITLE=" "$ZSHRC"; then
            sed -i '' '/^DISABLE_UNTRACKED_FILES_DIRTY=/a\
# 禁用自动设置终端标题\
DISABLE_AUTO_TITLE="true"' "$ZSHRC"
        fi
        log "✓ 已优化 git 目录性能"
    else
        log "[试运行] 将要设置 DISABLE_AUTO_UPDATE=\"true\""
        log "[试运行] 将要设置 DISABLE_UNTRACKED_FILES_DIRTY=\"true\""
        log "[试运行] 将要设置 DISABLE_AUTO_TITLE=\"true\""
    fi
}

# 启用插件
set_plugins() {
    log "配置插件..."
    local plugins="git z web-search"
    if [[ "$DRY_RUN" == "false" ]]; then
        sed -i '' 's/^plugins=.*/plugins=('"$plugins"')/' "$ZSHRC"
        log "✓ 插件已启用: $plugins"
    else
        log "[试运行] 将要设置 plugins=($plugins)"
    fi
}

# 安装 zsh-autosuggestions
install_autosuggestions() {
    local plugin_name="zsh-autosuggestions"
    local plugin_dir="${ZSH_CUSTOM}/plugins/${plugin_name}"

    log "安装 ${plugin_name}..."

    if [[ -d "$plugin_dir" ]]; then
        log "✓ ${plugin_name} 已安装，跳过"
    else
        if [[ "$DRY_RUN" == "false" ]]; then
            git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "$plugin_dir"
            log "✓ ${plugin_name} 安装完成"
        else
            log "[试运行] 将要克隆 https://github.com/zsh-users/zsh-autosuggestions.git 到 $plugin_dir"
        fi
    fi

    # 添加到 plugins
    if [[ "$DRY_RUN" == "false" ]]; then
        sed -i '' 's/plugins=(/plugins=(zsh-autosuggestions /' "$ZSHRC"
    fi
}

# 安装 zsh-syntax-highlighting
install_syntax_highlighting() {
    local plugin_name="zsh-syntax-highlighting"
    local plugin_dir="${ZSH_CUSTOM}/plugins/${plugin_name}"

    log "安装 ${plugin_name}..."

    if [[ -d "$plugin_dir" ]]; then
        log "✓ ${plugin_name} 已安装，跳过"
    else
        if [[ "$DRY_RUN" == "false" ]]; then
            git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$plugin_dir"
            log "✓ ${plugin_name} 安装完成"
        else
            log "[试运行] 将要克隆 https://github.com/zsh-users/zsh-syntax-highlighting.git 到 $plugin_dir"
        fi
    fi

    # 添加到 plugins (注意: zsh-syntax-highlighting 必须是最后一个)
    if [[ "$DRY_RUN" == "false" ]]; then
        sed -i '' 's/)/ zsh-syntax-highlighting)/' "$ZSHRC"
    fi
}

# 安装字体
install_font() {
    local font_name="font-meslo-lg-nerd-font"

    log "检查字体..."

    # 检查 Homebrew 是否安装
    if ! command -v brew &> /dev/null; then
        log "⚠ Homebrew 未安装，跳过字体自动安装"
        log "  如需安装字体，请先安装 Homebrew: https://brew.sh"
        return 0
    fi

    # 检查字体是否已安装
    if brew list --cask "$font_name" &> /dev/null; then
        log "✓ 字体 $font_name 已安装"
    else
        log "安装 $font_name ..."
        if [[ "$DRY_RUN" == "false" ]]; then
            brew install --cask "$font_name"
            log "✓ 字体安装完成"
            log "  请在终端设置中将字体更改为 'MesloLGS NF' 以显示特殊字符"
        else
            log "[试运行] 将要通过 brew 安装 $font_name"
        fi
    fi
}

# 主函数
main() {
    log "开始配置 Oh My Zsh..."
    log "运行模式: $([[ "$DRY_RUN" == "true" ]] && echo "试运行" || echo "实际执行")"
    echo

    check_ohmyzsh
    check_and_restore_pre_omz_config
    backup_zshrc
    set_theme
    disable_auto_update
    install_autosuggestions
    install_syntax_highlighting
    set_plugins
    install_font

    echo
    log "配置完成！"
    log "请运行 'source ~/.zshrc' 或重新打开终端以应用更改"

    if [[ "$DRY_RUN" == "false" ]]; then
        echo
        echo "提示:"
        echo "  - agnoster 主题使用 Meslo LG Nerd Font 字体显示特殊字符"
        echo "  - 如字体未自动生效，请在终端设置中手动选择 'MesloLGS NF'"
        echo "  - 配置完成后请运行 'source ~/.zshrc' 或重新打开终端"
    fi
}

main
