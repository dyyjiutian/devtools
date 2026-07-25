#!/usr/bin/env bash
# os/macos/remote-desktop/setup.sh — MacBook 盒盖 / 无显示器场景下的 VNC 虚拟屏配置
#
# 用途：安装虚拟显示器软件，创建虚拟屏，配合屏幕共享实现盒盖远程桌面。
#
# Usage:
#   ./setup.sh install              # 安装虚拟屏软件（Homebrew）
#   ./setup.sh configure            # 创建/连接虚拟屏 + 防睡 + 重启 VNC
#   ./setup.sh repair               # 重启后修复 VNC（重连虚拟屏 + 重启 screensharingd）
#   ./setup.sh status               # 诊断盒盖 / 虚拟屏 / VNC 状态
#   ./setup.sh nosleep              # 仅配置防睡（pmset + caffeinate -dims）
#   ./setup.sh help
#
# Environment:
#   VIRTUAL_BACKEND=betterdisplay|deskpad   默认 betterdisplay
#   VIRTUAL_SCREEN_NAME=HeadlessServer      BetterDisplay 虚拟屏名称
#   VIRTUAL_RESOLUTION=1920x1080            分辨率 WIDTHxHEIGHT
#   VIRTUAL_HIDPI=off|on                    默认 off（远程桌面 UI 更大）
#   SKIP_NOSLEEP=1                          跳过防睡配置

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NOSLEEP_SCRIPT="${REPO_ROOT}/os/macos/power/nosleep.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}▶ $*${RESET}"; }

VIRTUAL_BACKEND="${VIRTUAL_BACKEND:-betterdisplay}"
VIRTUAL_SCREEN_NAME="${VIRTUAL_SCREEN_NAME:-HeadlessServer}"
VIRTUAL_RESOLUTION="${VIRTUAL_RESOLUTION:-1920x1080}"
VIRTUAL_HIDPI="${VIRTUAL_HIDPI:-off}"

BD_APP="/Applications/BetterDisplay.app"
BD_CLI="${BD_APP}/Contents/MacOS/BetterDisplay"
DESKPAD_APP="/Applications/DeskPad.app"

CAFFEINATE_PID_FILE="/tmp/mac-remote-vnc.caffeinate.pid"
CAFFEINATE_LOG="/tmp/mac-remote-vnc.caffeinate.log"

require_macos() {
  [[ "$(uname)" == "Darwin" ]] || { error "此脚本仅支持 macOS"; exit 1; }
}

require_brew() {
  command -v brew >/dev/null 2>&1 || {
    error "未找到 Homebrew，请先安装: https://brew.sh"
    exit 1
  }
}

bd_cli() {
  [[ -x "$BD_CLI" ]] || { error "BetterDisplay 未安装: $BD_APP"; exit 1; }
  "$BD_CLI" "$@"
}

port_open() {
  local host="$1" port="$2"
  nc -G 3 -z "$host" "$port" >/dev/null 2>&1
}

manual_screen_sharing_note() {
  cat <<'EOF'

[WARN] 屏幕共享需在系统设置中手动开启（脚本无法可靠代劳）:
  macOS Monterey: 系统偏好设置 → 共享 → 勾选「屏幕共享」
  macOS Ventura+: 系统设置 → 通用 → 共享 → 屏幕共享

  首次从新设备连接时若弹出授权，请在开盖时点击「允许」。
EOF
}

install_backend() {
  require_brew
  step "安装虚拟屏软件: ${VIRTUAL_BACKEND}"

  case "$VIRTUAL_BACKEND" in
    betterdisplay)
      if [[ -d "$BD_APP" ]]; then
        success "BetterDisplay 已安装"
      else
        brew install --cask betterdisplay
        success "BetterDisplay 安装完成"
      fi
      ;;
    deskpad)
      if [[ -d "$DESKPAD_APP" ]]; then
        success "DeskPad 已安装"
      else
        brew install --cask deskpad
        success "DeskPad 安装完成"
      fi
      ;;
    *)
      error "未知 VIRTUAL_BACKEND: $VIRTUAL_BACKEND（可选: betterdisplay, deskpad）"
      exit 1
      ;;
  esac
}

start_betterdisplay() {
  if pgrep -x BetterDisplay >/dev/null 2>&1; then
    info "BetterDisplay 已在运行"
    return 0
  fi
  open -a BetterDisplay
  sleep 3
  pgrep -x BetterDisplay >/dev/null 2>&1 || {
    error "BetterDisplay 启动失败，请开盖手动打开应用"
    exit 1
  }
  success "BetterDisplay 已启动"
}

start_deskpad() {
  if pgrep -x DeskPad >/dev/null 2>&1; then
    info "DeskPad 已在运行"
    return 0
  fi
  open -a DeskPad
  sleep 3
  pgrep -x DeskPad >/dev/null 2>&1 || {
    error "DeskPad 启动失败，请开盖手动打开应用"
    exit 1
  }
  success "DeskPad 已启动"
}

configure_betterdisplay() {
  start_betterdisplay

  step "配置 BetterDisplay 虚拟屏: ${VIRTUAL_SCREEN_NAME} @ ${VIRTUAL_RESOLUTION}"

  # 若已存在则先移除，再按目标分辨率重建
  bd_cli discard -name="$VIRTUAL_SCREEN_NAME" 2>/dev/null || true
  sleep 1

  bd_cli create \
    -devicetype=virtualscreen \
    -virtualscreenname="$VIRTUAL_SCREEN_NAME" \
    -useResolutionList=on \
    -resolutionList="${VIRTUAL_RESOLUTION},2560x1440,1280x720" \
    -virtualScreenHiDPI=off \
    -connected=on 2>/dev/null || true

  sleep 2
  bd_cli set -name="$VIRTUAL_SCREEN_NAME" -resolution="$VIRTUAL_RESOLUTION" -hiDPI="$VIRTUAL_HIDPI" 2>/dev/null || true
  bd_cli set -name="$VIRTUAL_SCREEN_NAME" -connected=on 2>/dev/null || true

  local cur
  cur="$(bd_cli get -name="$VIRTUAL_SCREEN_NAME" -resolution -hiDPI 2>/dev/null || echo unknown)"
  success "BetterDisplay 虚拟屏: ${cur}"
}

configure_deskpad() {
  start_deskpad
  step "DeskPad 虚拟屏已启动"
  warn "请在 系统偏好设置 → 显示器 中选择 DeskPad Display，手动设置分辨率为 ${VIRTUAL_RESOLUTION}"
  warn "建议关闭 HiDPI 档位，选标准分辨率（远程桌面 UI 更大）"
}

apply_nosleep() {
  step "配置防睡（系统 + 磁盘 + 显示）"

  if [[ -f "$NOSLEEP_SCRIPT" ]]; then
    info "调用 ${NOSLEEP_SCRIPT} start"
    bash "$NOSLEEP_SCRIPT" start || warn "nosleep.sh 执行失败，尝试内置配置"
  fi

  sudo pmset -c sleep 0 displaysleep 0 autopoweroff 0 standby 0 powernap 0 2>/dev/null || \
    warn "pmset 需要 sudo 权限，部分防睡可能未生效"

  if [[ -f "$CAFFEINATE_PID_FILE" ]] && kill -0 "$(cat "$CAFFEINATE_PID_FILE")" 2>/dev/null; then
    info "caffeinate 已在运行 (PID $(cat "$CAFFEINATE_PID_FILE"))"
  else
    # -d 防止 display 睡眠，盒盖 VNC 关键
    nohup caffeinate -dims >>"$CAFFEINATE_LOG" 2>&1 &
    echo $! >"$CAFFEINATE_PID_FILE"
    success "caffeinate -dims 已启动 (PID $(cat "$CAFFEINATE_PID_FILE"))"
  fi
}

restart_screen_sharing() {
  step "重启屏幕共享服务 (screensharingd)"
  if sudo pkill screensharingd 2>/dev/null; then
    sleep 2
    success "screensharingd 已重启"
  else
    warn "无法 pkill screensharingd（需 sudo），尝试 launchctl kickstart（无 -k）"
    sudo launchctl kickstart system/com.apple.screensharing 2>/dev/null || \
      warn "重启屏幕共享失败，请手动在系统设置中开关「屏幕共享」"
    sleep 2
  fi
}

verify_vnc() {
  step "验证 VNC / SSH 端口"
  if port_open 127.0.0.1 22; then
    success "SSH  22  可用"
  else
    warn "SSH  22  不可用（请检查「远程登录」）"
  fi

  if port_open 127.0.0.1 5900; then
    success "VNC  5900 可用"
    return 0
  else
    warn "VNC  5900 不可用"
    return 1
  fi
}

show_status() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Mac 远程 VNC / 虚拟屏状态"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  echo "── 盒盖 / 显示 ──"
  ioreg -r -k AppleClamshellState -d 4 2>/dev/null | grep AppleClamshellState || true
  system_profiler SPDisplaysDataType 2>/dev/null | grep -E 'Display Type|Asleep|Resolution|Headless|DeskPad' || true
  echo ""

  echo "── 虚拟屏软件 ──"
  echo "  BACKEND=${VIRTUAL_BACKEND}"
  pgrep -lf 'BetterDisplay|DeskPad|screensharingd' 2>/dev/null || echo "  (无相关进程)"
  echo ""

  if [[ -x "$BD_CLI" ]]; then
    echo "── BetterDisplay 虚拟屏 ──"
    bd_cli get -name="$VIRTUAL_SCREEN_NAME" -resolution -hiDPI 2>/dev/null || echo "  ${VIRTUAL_SCREEN_NAME}: 未找到"
    echo ""
  fi

  echo "── 端口 ──"
  nc -G 2 -zv 127.0.0.1 22 2>&1 | sed 's/^/  /' || true
  nc -G 2 -zv 127.0.0.1 5900 2>&1 | sed 's/^/  /' || true
  echo ""

  echo "── 防睡 ──"
  pmset -g assertions 2>/dev/null | grep -E 'PreventUserIdleDisplaySleep|PreventSystemSleep|caffeinate' | head -6 || true
  echo ""
}

configure_all() {
  install_backend

  case "$VIRTUAL_BACKEND" in
    betterdisplay) configure_betterdisplay ;;
    deskpad)       configure_deskpad ;;
  esac

  if [[ "${SKIP_NOSLEEP:-0}" != "1" ]]; then
    apply_nosleep
  fi

  restart_screen_sharing
  manual_screen_sharing_note

  echo ""
  if verify_vnc; then
    success "配置完成，VNC 可用"
    info "连接: open vnc://$(ipconfig getifaddr en0 2>/dev/null || echo '<your-ip>')"
    info "或 SSH 隧道: ssh -L 5901:localhost:5900 user@host"
  else
    warn "VNC 仍不可用，请开盖完成屏幕共享授权，或检查虚拟屏是否已连接"
    info "运行 ./setup.sh repair 重试"
  fi
  echo ""
}

repair_vnc() {
  step "修复 VNC（重连虚拟屏 + 重启 screensharingd）"

  case "$VIRTUAL_BACKEND" in
    betterdisplay)
      [[ -x "$BD_CLI" ]] && start_betterdisplay && \
        bd_cli set -name="$VIRTUAL_SCREEN_NAME" -connected=on 2>/dev/null || true
      ;;
    deskpad)
      [[ -d "$DESKPAD_APP" ]] && start_deskpad || warn "DeskPad 未安装"
      ;;
  esac

  restart_screen_sharing
  sleep 2
  verify_vnc || {
    warn "仍无法连接，详见 README 故障排查"
    exit 1
  }
}

usage() {
  cat <<EOF
${BOLD}用法:${RESET}
  $(basename "$0") install     安装虚拟屏软件（brew cask）
  $(basename "$0") configure   完整配置（install + 虚拟屏 + 防睡 + VNC）
  $(basename "$0") repair      重启后修复 VNC
  $(basename "$0") status      诊断当前状态
  $(basename "$0") nosleep       仅配置防睡
  $(basename "$0") help

${BOLD}环境变量:${RESET}
  VIRTUAL_BACKEND         betterdisplay（默认）| deskpad（免费开源）
  VIRTUAL_SCREEN_NAME     BetterDisplay 虚拟屏名，默认 HeadlessServer
  VIRTUAL_RESOLUTION      默认 1920x1080
  VIRTUAL_HIDPI           默认 off
  SKIP_NOSLEEP=1          跳过防睡

${BOLD}示例:${RESET}
  # BetterDisplay（免费版可创建基础虚拟屏；自定义分辨率需 Pro）
  ./setup.sh configure

  # 免费开源替代（Monterey 12+）
  VIRTUAL_BACKEND=deskpad ./setup.sh configure

  # 2K 分辨率
  VIRTUAL_RESOLUTION=2560x1440 ./setup.sh configure

  # 重启后 VNC 挂了
  ./setup.sh repair

详见: os/macos/remote-desktop/README.md
EOF
}

main() {
  require_macos
  local cmd="${1:-help}"

  case "$cmd" in
    install)   install_backend ;;
    configure) configure_all ;;
    repair)    repair_vnc ;;
    status)    show_status ;;
    nosleep)   apply_nosleep ;;
    help|-h|--help) usage ;;
    *)
      error "未知命令: $cmd"
      usage
      exit 1
      ;;
  esac
}

main "$@"
