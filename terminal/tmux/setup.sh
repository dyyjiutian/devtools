#!/usr/bin/env bash
# ============================================================
# tmux Setup Script
# 安装 tmux、TPM 插件管理器，并部署本目录的 tmux.conf
# ============================================================

set -euo pipefail

info()    { echo -e "\033[34m[INFO]\033[0m $1"; }
success() { echo -e "\033[32m[OK]\033[0m $1"; }
warn()    { echo -e "\033[33m[WARN]\033[0m $1"; }
error()   { echo -e "\033[31m[ERROR]\033[0m $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_CONF_SRC="$SCRIPT_DIR/tmux.conf"
TMUX_CONF_DST="$HOME/.tmux.conf"
TPM_DIR="$HOME/.tmux/plugins/tpm"

# ────────────────────────────────────────────
# 帮助信息
# ────────────────────────────────────────────
show_help() {
    cat <<'EOF'
tmux Setup Script - 一键安装并配置 tmux

该脚本会执行以下步骤:
  1. 安装 tmux
     - macOS 通过 Homebrew 安装
     - Linux 通过 apt-get / yum / dnf 安装
  2. 备份已有的 ~/.tmux.conf（如果存在）
  3. 将本目录的 tmux.conf 软链接到 ~/.tmux.conf
  4. 安装 TPM（Tmux Plugin Manager）
  5. 通过 TPM 安装所有插件（tmux-sensible、vim-tmux-navigator、
     tmux-resurrect、tmux-continuum）

用法:
  ./setup.sh              运行完整安装
  ./setup.sh --dry-run    试运行，只显示将要执行的操作
  ./setup.sh --help       显示此帮助信息

快捷键速查（前缀键: Ctrl+Space）:
  Ctrl+Space r    重新加载配置
  Ctrl+Space c    新建 window（保持当前路径）
  Ctrl+Space |    垂直分割 pane（保持当前路径）
  Ctrl+Space -    水平分割 pane（保持当前路径）
  Ctrl+Space H/J/K/L    调整 pane 大小
  Ctrl+Space C-h/C-l    切换上/下一个 window
  Ctrl+Space Tab        在最近两个 window 间跳转
  C-h/j/k/l    在 pane 间移动（与 Vim 共用，需 vim-tmux-navigator）

复制模式（Vi 风格）:
  Ctrl+Space [    进入复制模式
  v              开始选择
  y              复制到系统剪贴板（macOS pbcopy）
  Ctrl+v         切换矩形选择

插件:
  tmux-resurrect    Ctrl+Space Ctrl+s 保存 / Ctrl+r 恢复 session
  tmux-continuum    每 15 分钟自动保存，启动时自动恢复
EOF
    exit 0
}

# ────────────────────────────────────────────
# 参数解析
# ────────────────────────────────────────────
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)    show_help ;;
        -d|--dry-run) DRY_RUN=true; shift ;;
        *)
            error "未知选项: $1\n       运行 ./setup.sh --help 查看用法"
            ;;
    esac
done

# dry-run 包装：打印意图或执行命令
run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [试运行] $*"
    else
        "$@"
    fi
}

# ────────────────────────────────────────────
# 操作系统检测
# ────────────────────────────────────────────
detect_os() {
    case "$(uname -s)" in
        Darwin*)  echo "macos" ;;
        Linux*)   echo "linux" ;;
        *)        echo "unknown" ;;
    esac
}

OS=$(detect_os)
info "检测到操作系统: $OS"
[[ "$DRY_RUN" == "true" ]] && warn "当前为试运行模式，不会实际修改任何文件"
echo

# ────────────────────────────────────────────
# 安装 tmux
# ────────────────────────────────────────────
install_tmux() {
    if command -v tmux &>/dev/null; then
        success "tmux 已安装: $(tmux -V)"
        return 0
    fi

    info "安装 tmux..."
    case "$OS" in
        macos)
            if ! command -v brew &>/dev/null; then
                error "Homebrew 未安装，请先安装: https://brew.sh"
            fi
            run brew install tmux
            ;;
        linux)
            if command -v apt-get &>/dev/null; then
                run sudo apt-get update -y
                run sudo apt-get install -y tmux
            elif command -v dnf &>/dev/null; then
                run sudo dnf install -y tmux
            elif command -v yum &>/dev/null; then
                run sudo yum install -y tmux
            else
                error "无法识别的包管理器，请手动安装 tmux"
            fi
            ;;
        *)
            error "不支持的操作系统，请手动安装 tmux"
            ;;
    esac
    success "tmux 安装完成"
}

# ────────────────────────────────────────────
# 部署 tmux.conf
# ────────────────────────────────────────────
deploy_config() {
    if [[ ! -f "$TMUX_CONF_SRC" ]]; then
        error "找不到配置文件: $TMUX_CONF_SRC"
    fi

    # 备份已有配置（非软链接时才备份）
    if [[ -f "$TMUX_CONF_DST" && ! -L "$TMUX_CONF_DST" ]]; then
        local backup="${TMUX_CONF_DST}.bak.$(date +%Y%m%d%H%M%S)"
        info "备份已有 ~/.tmux.conf 到 $backup"
        run cp "$TMUX_CONF_DST" "$backup"
    fi

    info "软链接 tmux.conf -> ~/.tmux.conf"
    run ln -sf "$TMUX_CONF_SRC" "$TMUX_CONF_DST"
    success "~/.tmux.conf -> $TMUX_CONF_SRC"
}

# ────────────────────────────────────────────
# 安装 TPM（Tmux Plugin Manager）
# ────────────────────────────────────────────
install_tpm() {
    if [[ -d "$TPM_DIR/.git" ]]; then
        success "TPM 已安装: $TPM_DIR"
        return 0
    fi

    if ! command -v git &>/dev/null; then
        error "需要 git 来安装 TPM，请先安装 git"
    fi

    info "安装 TPM..."
    run git clone --depth=1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
    success "TPM 安装完成"
}

# ────────────────────────────────────────────
# 安装 TPM 插件
# ────────────────────────────────────────────
install_plugins() {
    local install_script="$TPM_DIR/bin/install_plugins"

    if [[ "$DRY_RUN" == "true" ]]; then
        warn "[试运行] 将要运行 $install_script 安装所有 TPM 插件"
        return 0
    fi

    if [[ ! -x "$install_script" ]]; then
        warn "TPM install_plugins 脚本不存在，跳过插件安装"
        warn "请在 tmux 中手动按 Ctrl+Space + I 安装插件"
        return 0
    fi

    info "安装 TPM 插件（首次可能需要一点时间）..."
    # 需要一个活跃的 tmux 服务端才能运行 install_plugins；若不在 tmux 内则跳过
    if [[ -n "${TMUX:-}" ]]; then
        "$install_script"
        success "TPM 插件安装完成"
    else
        warn "当前不在 tmux 会话中，无法自动安装插件"
        warn "请启动 tmux 后按 Ctrl+Space + I 完成插件安装"
    fi
}

# ────────────────────────────────────────────
# 主流程
# ────────────────────────────────────────────
main() {
    install_tmux
    deploy_config
    install_tpm
    install_plugins

    echo
    success "tmux 配置完成！"
    echo
    echo "  前缀键: Ctrl+Space"
    echo
    echo "  后续操作:"
    if [[ -z "${TMUX:-}" ]]; then
        echo "    1. 启动 tmux"
        echo "    2. 按 Ctrl+Space + I  安装 TPM 插件（首次）"
    else
        echo "    1. 按 Ctrl+Space + I  安装 TPM 插件（首次）"
        echo "    2. 按 Ctrl+Space + r  重新加载配置"
    fi
    echo
    echo "  运行 ./setup.sh --help 查看完整快捷键速查"
    echo
}

main
