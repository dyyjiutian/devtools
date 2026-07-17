#!/usr/bin/env bash
# 安装独立的 setproxy 与 speed_test 命令到 ~/.local/bin。
#
# bin/setproxy 是自包含脚本，安装后即使删除本仓库依然可用（与 git 子命令
# 的安装方式一致，见 vcs/git/scripts/sub-command.sh）。
#
# 支持 macOS / Linux。卸载时会一并清理安装器和 setproxy 写入的配置块，
# 但不会修改 ~/.ssh/config，也不会停止 V2RayXS / Xray 进程。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/bin/setproxy"
SPEED_TEST_SRC="${SCRIPT_DIR}/bin/speed_test"
LOCAL_BIN_DIR="${HOME}/.local/bin"
DST="${LOCAL_BIN_DIR}/setproxy"
SPEED_TEST_DST="${LOCAL_BIN_DIR}/speed_test"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RESET='\033[0m'
info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*" >&2; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

usage() {
    cat <<'HELP'
用法:
  ./install-setproxy.sh              安装 setproxy 和 speed_test 到 ~/.local/bin
  ./install-setproxy.sh --dry-run    仅预览，不实际执行
  ./install-setproxy.sh --uninstall  卸载 setproxy 和 speed_test

安装完成后:
  setproxy on | off | status | test [--size MB]
  speed_test [--size MB] [--vpn-port PORT]
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

PATH_MARKER_BEGIN="# >>> devtools setproxy PATH >>>"
PATH_MARKER_END="# <<< devtools setproxy PATH <<<"
LEGACY_PATH_MARKER="# devtools setproxy PATH"
PATH_LINE='[[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"'
SIMPLE_PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
PROXY_MARKER_BEGIN="# >>> vpn-shell-proxy managed >>>"
PROXY_MARKER_END="# <<< vpn-shell-proxy managed <<<"

remove_managed_block() {
    local file="$1" begin="$2" end="$3" tmp
    [[ -f "$file" ]] || return 0
    tmp="${file}.setproxy.$$"
    awk -v begin="$begin" -v end="$end" '
        $0 == begin { skip=1; next }
        skip && $0 == end { skip=0; next }
        !skip { print }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
}

remove_legacy_path_block() {
    local file="$1" tmp
    [[ -f "$file" ]] || return 0
    tmp="${file}.setproxy.$$"
    awk -v marker="$LEGACY_PATH_MARKER" -v line="$PATH_LINE" '
        $0 == marker { skip_line=1; next }
        skip_line && $0 == line { skip_line=0; next }
        { skip_line=0; print }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
}

cleanup_rc_file() {
    local file="$1"
    remove_managed_block "$file" "$PATH_MARKER_BEGIN" "$PATH_MARKER_END"
    remove_managed_block "$file" "$PROXY_MARKER_BEGIN" "$PROXY_MARKER_END"
    remove_legacy_path_block "$file"
}

warn_legacy_functions() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    if grep -Eq '^[[:space:]]*(function[[:space:]]+)?(setproxy|unsetproxy)[[:space:]]*\(\)' "$file"; then
        warn "${file} 中已有 setproxy/unsetproxy 函数，建议注释后使用独立命令，避免同名覆盖"
    fi
}

if $UNINSTALL; then
    if $DRY_RUN; then
        info "[dry-run] 将删除 ${DST} 和 ${SPEED_TEST_DST}"
        info "[dry-run] 将清理 shell 配置中的 setproxy 管理块"
        info "[dry-run] 将删除 ${HOME}/.config/vpn/proxy.env 和 setproxy.conf"
    else
        rm -f "$DST" "$SPEED_TEST_DST"
        for rc_file in "${HOME}/.zshrc" "${HOME}/.bashrc" "${HOME}/.profile"; do
            cleanup_rc_file "$rc_file"
        done
        rm -f "${HOME}/.config/vpn/proxy.env" "${HOME}/.config/vpn/setproxy.conf"
        rmdir "${HOME}/.config/vpn" 2>/dev/null || true
        rmdir "${HOME}/.config" 2>/dev/null || true
        success "已卸载 setproxy、speed_test，并清理其 shell 钩子和代理配置"
        warn "代理客户端进程未停止，~/.ssh/config 未修改"
    fi
    exit 0
fi

if [[ ! -f "$SRC" || ! -f "$SPEED_TEST_SRC" ]]; then
    error "未找到 ${SRC} 或 ${SPEED_TEST_SRC}"
    exit 1
fi

if $DRY_RUN; then
    info "[dry-run] 将安装 ${SRC} → ${DST}"
    info "[dry-run] 将安装 ${SPEED_TEST_SRC} → ${SPEED_TEST_DST}"
else
    mkdir -p "$LOCAL_BIN_DIR"
    install -m 0755 "$SRC" "$DST"
    install -m 0755 "$SPEED_TEST_SRC" "$SPEED_TEST_DST"
    success "已安装 setproxy: ${DST}"
    success "已安装 speed_test: ${SPEED_TEST_DST}"
fi

RC_FILE="$(detect_rc_file)"
warn_legacy_functions "$RC_FILE"

if [[ -f "$RC_FILE" ]] && grep -qF "$PATH_MARKER_BEGIN" "$RC_FILE" 2>/dev/null; then
    info "${LOCAL_BIN_DIR} 已在 PATH 配置中，跳过"
elif [[ -f "$RC_FILE" ]] && {
    grep -qF "$PATH_LINE" "$RC_FILE" 2>/dev/null ||
    grep -qF "$SIMPLE_PATH_LINE" "$RC_FILE" 2>/dev/null
}; then
    info "${LOCAL_BIN_DIR} 已在 ${RC_FILE} 的 PATH 中，跳过"
elif $DRY_RUN; then
    info "[dry-run] 将把 ${LOCAL_BIN_DIR} 加入 ${RC_FILE}"
else
    touch "$RC_FILE"
    remove_legacy_path_block "$RC_FILE"
    {
        printf '\n%s\n' "$PATH_MARKER_BEGIN"
        printf '%s\n' "$PATH_LINE"
        printf '%s\n' "$PATH_MARKER_END"
    } >> "$RC_FILE"
    success "已将 ${LOCAL_BIN_DIR} 加入 ${RC_FILE}"
fi

echo ""
if $DRY_RUN; then
    echo "[DRY RUN] 未做任何更改。移除 --dry-run 以实际执行。"
else
    success "安装完成！新开终端后即可直接使用:"
    echo "  setproxy on | off | status | test [--size MB]"
    echo "  speed_test [--size MB] [--vpn-port PORT]"
    warn "当前终端需先执行: export PATH=\"\$HOME/.local/bin:\$PATH\"  或重新打开终端"
    info "Git SSH 代理由 GIT_SSH_COMMAND 实现，不会修改 ~/.ssh/config"
fi
