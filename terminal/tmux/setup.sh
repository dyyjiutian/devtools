#!/usr/bin/env bash
# ============================================================
# tmux Setup Script
# 安装 tmux 3.7b、TPM 插件管理器，并部署本目录的 tmux.conf
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

# 目标版本：RHEL/Alinux 系统包过旧（常为 2.7），统一安装 3.7b 以支持 extended-keys
TMUX_VERSION="${TMUX_VERSION:-3.7b}"
TMUX_TARBALL="tmux-${TMUX_VERSION}.tar.gz"
TMUX_URL="https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/${TMUX_TARBALL}"
# 用户安装默认 ~/.local；系统初始化可设 TMUX_PREFIX=/usr/local
TMUX_PREFIX="${TMUX_PREFIX:-$HOME/.local}"
CACHE_DIR="${DEVTOOLS_CACHE_DIR:-${SCRIPT_DIR}/../../cache}"

# ────────────────────────────────────────────
# 帮助信息
# ────────────────────────────────────────────
show_help() {
    cat <<EOF
tmux Setup Script - 一键安装并配置 tmux ${TMUX_VERSION}

该脚本会执行以下步骤:
  1. 检测 tmux 版本，判断是否已满足目标 ${TMUX_VERSION}
     - 已满足: 跳过安装/编译，直接部署配置
     - 未满足 (缺失或过旧):
       · 不带 --upgrade: 跳过强制安装/编译，仅警告并提示使用 --upgrade
       · 带 --upgrade: 优先包管理器升级 (brew / apt-get / dnf / yum)，
         仍不满足则回退到源码编译安装到 \${TMUX_PREFIX}（默认 ~/.local），
         并移除过旧的发行版包（如 Alinux/CentOS 的 2.7）
  2. 备份已有的 ~/.tmux.conf（如果存在）
  3. 将本目录的 tmux.conf 复制到 ~/.tmux.conf（覆盖）
  4. 安装 TPM（Tmux Plugin Manager）
  5. 通过 TPM 安装所有插件（tmux-sensible、vim-tmux-navigator、
     tmux-resurrect、tmux-continuum）

用法:
  ./setup.sh                     运行完整安装（不强制升级 tmux 二进制）
  ./setup.sh --upgrade           升级 tmux 到目标版本后完整安装
  ./setup.sh --install-bin-only  仅安装/升级 tmux 二进制
  ./setup.sh --dry-run           试运行，只显示将要执行的操作
  ./setup.sh --help              显示此帮助信息

  可组合使用，例如: ./setup.sh --upgrade --dry-run
                   ./setup.sh --upgrade --install-bin-only

环境变量:
  TMUX_VERSION   目标版本（默认 ${TMUX_VERSION}）
  TMUX_PREFIX    安装前缀（默认 \$HOME/.local；系统装可用 /usr/local）
  DEVTOOLS_CACHE_DIR  离线缓存根目录（默认仓库 cache/）

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
INSTALL_BIN_ONLY=false
DO_UPGRADE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)            show_help ;;
        -d|--dry-run)         DRY_RUN=true; shift ;;
        -u|--upgrade)         DO_UPGRADE=true; shift ;;
        --install-bin-only)   INSTALL_BIN_ONLY=true; shift ;;
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

# 需要 root 时用 sudo（已是 root 则直接执行）
run_root() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [试运行] $*"
        return 0
    fi
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
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
# 版本检测与比较
# ────────────────────────────────────────────
# 取某个 tmux 可执行文件的版本号原始字符串，例如 "3.7b"
_tmux_version_string() {
    local bin="$1"
    [[ -n "$bin" && -x "$bin" ]] || return 1
    "$bin" -V 2>/dev/null | awk '{print $2}'
}

# 归一化版本号为 major.minor.patch，供数值比较；结尾字母 (a/b/c...) 映射为 patch (1/2/3...)
# 例如: "3.7b" -> "3.7.2"，"3.9" -> "3.9.0"
_tmux_normalize_version() {
    local v="${1:-}" major minor letter patch
    [[ -n "$v" ]] || { echo "0.0.0"; return 0; }

    major=$(echo "$v" | sed -E 's/^([0-9]+).*/\1/')
    minor=$(echo "$v" | sed -E 's/^[0-9]+\.([0-9]+).*/\1/')
    letter=$(echo "$v" | sed -E 's/^[0-9]+\.[0-9]+([a-zA-Z]?).*/\1/')

    patch=0
    if [[ -n "$letter" ]]; then
        letter=$(echo "$letter" | tr '[:upper:]' '[:lower:]')
        patch=$(( $(printf '%d' "'$letter") - $(printf '%d' "'a") + 1 ))
    fi

    echo "${major:-0}.${minor:-0}.${patch}"
}

# 比较归一化版本；$1 >= $2 时输出 "ge"，否则 "lt"
version_ge() {
    local a="$1" b="$2"
    local IFS=.
    # shellcheck disable=SC2086
    set -- $a
    local a1="${1:-0}" a2="${2:-0}" a3="${3:-0}"
    # shellcheck disable=SC2086
    set -- $b
    local b1="${1:-0}" b2="${2:-0}" b3="${3:-0}"

    if ((a1 > b1)); then echo "ge"; return; fi
    if ((a1 < b1)); then echo "lt"; return; fi
    if ((a2 > b2)); then echo "ge"; return; fi
    if ((a2 < b2)); then echo "lt"; return; fi
    if ((a3 >= b3)); then echo "ge"; return; fi
    echo "lt"
}

# 当前生效的 tmux 版本：优先 TMUX_PREFIX 下的托管安装，其次 PATH 中的 tmux
tmux_effective_version() {
    local v
    if [[ -x "${TMUX_PREFIX}/bin/tmux" ]]; then
        v=$(_tmux_version_string "${TMUX_PREFIX}/bin/tmux") || v=""
        [[ -n "$v" ]] && { echo "$v"; return 0; }
    fi
    if command -v tmux &>/dev/null; then
        v=$(_tmux_version_string "$(command -v tmux)") || v=""
        [[ -n "$v" ]] && { echo "$v"; return 0; }
    fi
    echo ""
}

# 当前 tmux 是否已满足目标版本 (>=)
tmux_meets_target() {
    local cur="$1"
    [[ -n "$cur" ]] || return 1
    [[ "$(version_ge "$(_tmux_normalize_version "$cur")" "$(_tmux_normalize_version "$TMUX_VERSION")")" == "ge" ]]
}

# ────────────────────────────────────────────
# 确保 ~/.local/bin 在 PATH（用户级安装）
# ────────────────────────────────────────────
ensure_local_path() {
    local bindir="${TMUX_PREFIX}/bin"
    [[ "$bindir" == "$HOME/.local/bin" ]] || return 0

    mkdir -p "$bindir"
    case ":$PATH:" in
        *":${bindir}:"*) ;;
        *) export PATH="${bindir}:$PATH" ;;
    esac

    local line='export PATH="$HOME/.local/bin:$PATH"'
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$rc" ]] || continue
        if ! grep -qF '.local/bin' "$rc" 2>/dev/null; then
            info "将 $bindir 写入 $(basename "$rc")"
            run bash -c "printf '\n# tmux / local bins\n%s\n' '$line' >> '$rc'"
        fi
    done
}

# ────────────────────────────────────────────
# 移除过旧的发行版 tmux（避免 /usr/bin/tmux 抢 PATH）
# ────────────────────────────────────────────
remove_distro_tmux() {
    local pkg_tmux=""
    if command -v rpm &>/dev/null && rpm -q tmux &>/dev/null 2>&1; then
        pkg_tmux=$(rpm -q tmux)
    elif command -v dpkg-query &>/dev/null && dpkg-query -W -f='${Status}' tmux 2>/dev/null | grep -q 'install ok installed'; then
        pkg_tmux=$(dpkg-query -W -f='${Package} ${Version}' tmux 2>/dev/null)
    else
        return 0
    fi

    warn "检测到发行版 tmux 包（${pkg_tmux}），将移除以免覆盖 ${TMUX_VERSION}"
    if command -v dnf &>/dev/null; then
        run_root dnf remove -y tmux
    elif command -v yum &>/dev/null; then
        run_root yum remove -y tmux
    elif command -v apt-get &>/dev/null; then
        run_root apt-get remove -y tmux
    else
        warn "无法自动移除发行版 tmux，请手动卸载"
    fi
}

# ────────────────────────────────────────────
# Linux：安装编译依赖
# ────────────────────────────────────────────
install_build_deps_linux() {
    info "安装编译依赖 (libevent, ncurses, bison, gcc, make)..."
    if command -v apt-get &>/dev/null; then
        run_root apt-get update -y
        run_root apt-get install -y build-essential libevent-dev libncurses-dev bison pkg-config curl
    elif command -v dnf &>/dev/null; then
        run_root dnf install -y gcc make libevent-devel ncurses-devel bison pkgconfig curl
    elif command -v yum &>/dev/null; then
        run_root yum install -y gcc make libevent-devel ncurses-devel bison pkgconfig curl
    else
        error "无法识别的包管理器，请手动安装 libevent/ncurses 开发包后重试"
    fi
}

# ────────────────────────────────────────────
# Linux：从源码编译安装
# ────────────────────────────────────────────
install_tmux_from_source() {
    local tmpdir tarball srcdir
    tmpdir=$(mktemp -d)
    tarball="${tmpdir}/${TMUX_TARBALL}"
    srcdir="${tmpdir}/tmux-${TMUX_VERSION}"

    # 清理钩子
    # shellcheck disable=SC2064
    trap "rm -rf '$tmpdir'" RETURN

    if [[ -f "${CACHE_DIR}/binaries/${TMUX_TARBALL}" ]]; then
        info "使用本地缓存: binaries/${TMUX_TARBALL}"
        run cp "${CACHE_DIR}/binaries/${TMUX_TARBALL}" "$tarball"
    else
        info "下载 tmux ${TMUX_VERSION}..."
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [试运行] curl -fL -o $tarball $TMUX_URL"
        else
            curl -fL --retry 3 -o "$tarball" "$TMUX_URL"
        fi
    fi

    info "编译安装到 ${TMUX_PREFIX} ..."
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [试运行] tar xf $tarball && ./configure --prefix=$TMUX_PREFIX && make && make install"
        return 0
    fi

    tar xf "$tarball" -C "$tmpdir"
    (
        cd "$srcdir"
        ./configure --prefix="$TMUX_PREFIX"
        make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
        make install
    )

    [[ -x "${TMUX_PREFIX}/bin/tmux" ]] || error "安装失败：找不到 ${TMUX_PREFIX}/bin/tmux"
    success "tmux 已安装: $("${TMUX_PREFIX}/bin/tmux" -V) -> ${TMUX_PREFIX}/bin/tmux"
}

# ────────────────────────────────────────────
# macOS：优先包管理器升级/安装
# ────────────────────────────────────────────
upgrade_tmux_macos() {
    if ! command -v brew &>/dev/null; then
        error "Homebrew 未安装，请先安装: https://brew.sh"
    fi
    if brew list tmux &>/dev/null; then
        run brew upgrade tmux || run brew install tmux
    else
        run brew install tmux
    fi
    hash -r 2>/dev/null || true

    if [[ "$DRY_RUN" != "true" ]] && command -v tmux &>/dev/null; then
        local brew_ver
        brew_ver=$(tmux -V | awk '{print $2}')
        if tmux_meets_target "$brew_ver"; then
            success "tmux 安装完成: $(tmux -V)"
        else
            warn "Homebrew tmux 版本为 ${brew_ver}（目标 ${TMUX_VERSION}）；通常可用，extended-keys 需 >= 3.2"
        fi
    fi
}

# ────────────────────────────────────────────
# Linux：优先包管理器升级，不足则回退源码编译
# ────────────────────────────────────────────
upgrade_tmux_linux() {
    info "尝试通过包管理器升级 tmux..."
    if command -v apt-get &>/dev/null; then
        run_root apt-get update -y
        run_root apt-get install -y --only-upgrade tmux || run_root apt-get install -y tmux || true
    elif command -v dnf &>/dev/null; then
        run_root dnf upgrade -y tmux || run_root dnf install -y tmux || true
    elif command -v yum &>/dev/null; then
        run_root yum update -y tmux || run_root yum install -y tmux || true
    else
        warn "无法识别的包管理器，跳过包管理器升级"
    fi
    hash -r 2>/dev/null || true

    if [[ "$DRY_RUN" != "true" ]]; then
        local pkg_ver=""
        if command -v tmux &>/dev/null; then
            pkg_ver=$(tmux -V 2>/dev/null | awk '{print $2}')
        fi
        if [[ -n "$pkg_ver" ]] && tmux_meets_target "$pkg_ver"; then
            success "包管理器 tmux ${pkg_ver} 已满足目标 ${TMUX_VERSION}"
            return 0
        fi
        if [[ -n "$pkg_ver" ]]; then
            warn "包管理器后 tmux 仍为 ${pkg_ver}（目标 ${TMUX_VERSION}），回退到源码安装"
        else
            warn "包管理器未能提供 tmux，回退到源码安装"
        fi
    else
        info "[试运行] 若包管理器版本不足目标 ${TMUX_VERSION}，将回退到源码编译安装"
    fi

    remove_distro_tmux
    install_build_deps_linux
    mkdir -p "${TMUX_PREFIX}/bin"
    install_tmux_from_source
    ensure_local_path
    hash -r 2>/dev/null || true
    if command -v tmux &>/dev/null; then
        success "PATH 中的 tmux: $(command -v tmux) ($(tmux -V))"
    fi
}

# ────────────────────────────────────────────
# 安装 tmux
# ────────────────────────────────────────────
install_tmux() {
    local cur
    cur=$(tmux_effective_version)

    if tmux_meets_target "$cur"; then
        success "tmux ${cur} 已满足目标 ${TMUX_VERSION}，跳过安装/编译"
        # 仍尝试清掉发行版旧包，避免 PATH 冲突
        remove_distro_tmux
        ensure_local_path
        hash -r 2>/dev/null || true
        return 0
    fi

    if [[ "$DO_UPGRADE" != "true" ]]; then
        if [[ -z "$cur" ]]; then
            warn "未检测到 tmux，跳过强制安装/编译"
        else
            warn "当前 tmux ${cur} 低于目标 ${TMUX_VERSION}，跳过强制升级/编译"
        fi
        warn "如需安装/升级到 ${TMUX_VERSION}，请运行: ./setup.sh --upgrade"
        return 0
    fi

    info "当前 tmux: ${cur:-未安装} → 升级到 ${TMUX_VERSION}"

    case "$OS" in
        macos)
            upgrade_tmux_macos
            ;;
        linux)
            upgrade_tmux_linux
            ;;
        *)
            error "不支持的操作系统，请手动安装 tmux ${TMUX_VERSION}"
            ;;
    esac
}

# ────────────────────────────────────────────
# 部署 tmux.conf
# ────────────────────────────────────────────
deploy_config() {
    if [[ ! -f "$TMUX_CONF_SRC" ]]; then
        error "找不到配置文件: $TMUX_CONF_SRC"
    fi

    # 备份已有普通文件；已有软链则先删除，避免 cp 写穿到源文件
    if [[ -L "$TMUX_CONF_DST" ]]; then
        info "移除已有软链接 ~/.tmux.conf"
        run rm -f "$TMUX_CONF_DST"
    elif [[ -f "$TMUX_CONF_DST" ]]; then
        local backup="${TMUX_CONF_DST}.bak.$(date +%Y%m%d%H%M%S)"
        info "备份已有 ~/.tmux.conf 到 $backup"
        run cp "$TMUX_CONF_DST" "$backup"
    fi

    info "复制 tmux.conf -> ~/.tmux.conf"
    run cp "$TMUX_CONF_SRC" "$TMUX_CONF_DST"
    success "已安装 ~/.tmux.conf"
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

    if [[ "$INSTALL_BIN_ONLY" == "true" ]]; then
        echo
        success "tmux 二进制处理完成（--install-bin-only）"
        return 0
    fi

    deploy_config
    install_tpm
    install_plugins

    echo
    success "tmux 配置完成！"
    echo
    echo "  版本:   tmux ${TMUX_VERSION}（extended-keys / Shift+Enter 换行）"
    echo "  前缀键: Ctrl+Space"
    echo
    echo "  后续操作:"
    if [[ -z "${TMUX:-}" ]]; then
        echo "    1. 启动 tmux（若刚升级过，先结束旧 server: tmux kill-server）"
        echo "    2. 按 Ctrl+Space + I  安装 TPM 插件（首次）"
    else
        echo "    1. 按 Ctrl+Space + I  安装 TPM 插件（首次）"
        echo "    2. 按 Ctrl+Space + r  重新加载配置"
    fi
    echo
    echo "  运行 ./setup.sh --help 查看完整快捷键速查"
    echo
}

if [[ "${SETUP_NO_MAIN:-false}" != "true" && "${SETUP_NO_MAIN:-false}" != "1" ]]; then
    main
fi
