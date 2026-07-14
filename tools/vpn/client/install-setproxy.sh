#!/usr/bin/env bash
# 安装独立的 setproxy 命令到 ~/.local/bin，之后可在任意目录直接执行:
#   setproxy on | off | status | test
#
# bin/setproxy 是自包含脚本，安装后即使删除本仓库依然可用（与 git 子命令
# 的安装方式一致，见 vcs/git/scripts/sub-command.sh）。
#
# 用法:
#   ./install-setproxy.sh              安装 setproxy 命令
#   ./install-setproxy.sh --dry-run    仅预览，不实际执行
#   ./install-setproxy.sh --uninstall  卸载 setproxy 命令

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/bin/setproxy"
LOCAL_BIN_DIR="${HOME}/.local/bin"
DST="${LOCAL_BIN_DIR}/setproxy"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RESET='\033[0m'
info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

usage() {
    cat <<'HELP'
用法:
  ./install-setproxy.sh              安装 setproxy 命令到 ~/.local/bin
  ./install-setproxy.sh --dry-run    仅预览，不实际执行
  ./install-setproxy.sh --uninstall  卸载 setproxy 命令

安装完成后:
  setproxy on | off | status | test
HELP
}

DRY_RUN=false
UNINSTALL=false
for arg in "$@"; do
    case "$arg" in
        --help|-h)   usage; exit 0 ;;
        --dry-run)   DRY_RUN=true ;;
        --uninstall) UNINSTALL=true ;;
        *) error "未知参数: $arg"; usage; exit 1 ;;
    esac
done

detect_rc_file() {
    local shell_name
    shell_name="$(basename "${SHELL:-}")"
    case "$shell_name" in
        zsh)  echo "${HOME}/.zshrc" ;;
        bash) echo "${HOME}/.bashrc" ;;
        *)
            if [[ -f "${HOME}/.zshrc" ]]; then echo "${HOME}/.zshrc"
            else echo "${HOME}/.bashrc"
            fi
            ;;
    esac
}

if $UNINSTALL; then
    if $DRY_RUN; then
        info "[dry-run] 将删除 ${DST}"
    else
        rm -f "$DST"
        success "已卸载 setproxy（${DST}）"
    fi
    exit 0
fi

if [[ ! -f "$SRC" ]]; then
    error "未找到 ${SRC}"
    exit 1
fi

if $DRY_RUN; then
    info "[dry-run] 将安装 ${SRC} → ${DST}"
else
    mkdir -p "$LOCAL_BIN_DIR"
    install -m 0755 "$SRC" "$DST"
    success "已安装 setproxy: ${DST}"
fi

RC_FILE="$(detect_rc_file)"
MARKER="# devtools setproxy PATH"
LINE='[[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"'

if [[ -f "$RC_FILE" ]] && grep -qF "$MARKER" "$RC_FILE" 2>/dev/null; then
    info "${LOCAL_BIN_DIR} 已在 PATH 配置中，跳过"
elif $DRY_RUN; then
    info "[dry-run] 将把 ${LOCAL_BIN_DIR} 加入 ${RC_FILE}"
else
    {
        printf '\n%s\n' "$MARKER"
        printf '%s\n' "$LINE"
    } >> "$RC_FILE"
    success "已将 ${LOCAL_BIN_DIR} 加入 ${RC_FILE}"
fi

echo ""
if $DRY_RUN; then
    echo "[DRY RUN] 未做任何更改。移除 --dry-run 以实际执行。"
else
    success "安装完成！新开终端后即可直接使用:"
    echo "  setproxy on | off | status | test"
    warn "当前终端需先执行: export PATH=\"\$HOME/.local/bin:\$PATH\"  或重新打开终端"
fi
