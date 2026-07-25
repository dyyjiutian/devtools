#!/usr/bin/env bash
# nosleep.sh — Keep macOS awake and network alive when lid is closed or screen is locked.
#
# Usage:
#   ./nosleep.sh start    # Enable no-sleep mode (requires sudo for pmset)
#   ./nosleep.sh stop     # Restore original power settings
#   ./nosleep.sh status   # Show current state
#   ./nosleep.sh help

set -euo pipefail

# ── Constants ──────────────────────────────────────────────────────────────────
SCRIPT_NAME="nosleep"
PID_FILE="/tmp/${SCRIPT_NAME}.pid"
BACKUP_FILE="/tmp/${SCRIPT_NAME}.pmset.bak"
LOG_FILE="/tmp/${SCRIPT_NAME}.log"

# ── Colors ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
step()    { echo -e "${CYAN}[STEP]${RESET}  $*"; }

# ── Helpers ────────────────────────────────────────────────────────────────────
require_macos() {
  [[ "$(uname)" == "Darwin" ]] || { error "This script requires macOS."; exit 1; }
}

is_running() {
  [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

backup_pmset() {
  pmset -g custom > "$BACKUP_FILE" 2>/dev/null || true
  info "Power settings backed up to $BACKUP_FILE"
}

restore_pmset() {
  if [[ ! -f "$BACKUP_FILE" ]]; then
    warn "No backup found, skipping pmset restore."
    return
  fi

  # Parse and restore key values from backup
  local restore_sleep restore_disksleep
  restore_sleep=$(grep -E '^\s+sleep\s' "$BACKUP_FILE" | awk '{print $2}' | head -1 || echo 1)
  restore_disksleep=$(grep -E '^\s+disksleep\s' "$BACKUP_FILE" | awk '{print $2}' | head -1 || echo 10)

  sudo pmset -a sleep        "${restore_sleep:-1}"      2>/dev/null || true
  sudo pmset -a disksleep    "${restore_disksleep:-10}" 2>/dev/null || true
  sudo pmset -a tcpkeepalive 1                          2>/dev/null || true
  sudo pmset -a powernap     1                          2>/dev/null || true
  rm -f "$BACKUP_FILE"
  success "Power settings restored."
}

apply_pmset() {
  step "Configuring pmset power management..."

  # Disable sleep timers so lid-close / idle don't trigger sleep
  sudo pmset -a sleep     0   # No system sleep
  sudo pmset -a disksleep 0   # No disk sleep

  # Keep network alive during sleep / Power Nap
  sudo pmset -a tcpkeepalive 1   # Maintain TCP connections during sleep
  sudo pmset -a powernap     1   # Background network activity (mail, iCloud …)

  # Disable hibernation to avoid losing RAM state (faster wake, no swap write)
  sudo pmset -a hibernatemode 0

  success "pmset configured: sleep disabled, TCP keep-alive on, Power Nap on."
}

start_caffeinate() {
  step "Starting caffeinate..."

  # -s  prevent system sleep while on AC power
  # -i  prevent idle sleep
  # -d  prevent display sleep (remove if you want screen to dim/off)
  # -m  prevent disk from sleeping
  nohup caffeinate -s -i -m >> "$LOG_FILE" 2>&1 &
  local pid=$!
  echo "$pid" > "$PID_FILE"
  success "caffeinate started (PID $pid, log: $LOG_FILE)."
}

stop_caffeinate() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" && success "caffeinate (PID $pid) stopped."
    else
      warn "caffeinate PID $pid not found (already dead)."
    fi
    rm -f "$PID_FILE"
  else
    warn "No PID file found; caffeinate may not be running."
  fi
}

show_status() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  nosleep status"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if is_running; then
    success "nosleep is ACTIVE (caffeinate PID $(cat "$PID_FILE"))"
  else
    warn "nosleep is INACTIVE"
  fi

  echo ""
  echo "── caffeinate assertions ────────────"
  pmset -g assertions 2>/dev/null | grep -E 'PreventUserIdleSystem|PreventSystemSleep|caffeinate' || echo "  (none)"

  echo ""
  echo "── current pmset (AC) ───────────────"
  pmset -g custom 2>/dev/null | grep -E 'sleep|powernap|tcpkeepalive|hibernate' || true

  echo ""
}

show_help() {
  cat <<EOF
nosleep.sh — Keep macOS awake and networked (lid closed / screen locked)

Usage:
  $(basename "$0") start    Enable no-sleep mode
  $(basename "$0") stop     Restore original settings & stop caffeinate
  $(basename "$0") status   Show current state
  $(basename "$0") help     Show this help

How it works:
  • caffeinate -s -i -m   holds system/idle/disk wake assertions
  • pmset sleep 0         disables the sleep timer entirely
  • pmset tcpkeepalive 1  keeps TCP connections alive (SSH, HTTPS …)
  • pmset powernap 1      allows background network tasks during display-off

Notes:
  • sudo is required for pmset changes.
  • For lid-close scenarios, make sure the Mac is on AC power.
  • To also keep the DISPLAY on, edit start_caffeinate and add the -d flag.
  • Stop restores your original sleep/disksleep values from the backup.
EOF
}

# ── Main ───────────────────────────────────────────────────────────────────────
require_macos

case "${1:-help}" in
  start)
    if is_running; then
      warn "nosleep is already running (PID $(cat "$PID_FILE")). Run 'stop' first."
      exit 0
    fi
    echo ""
    info "Starting nosleep mode..."
    backup_pmset
    apply_pmset
    start_caffeinate
    echo ""
    success "nosleep is ON. Network will stay alive with lid closed / screen locked."
    echo "  Run '$(basename "$0") stop' to restore normal power settings."
    echo ""
    ;;

  stop)
    echo ""
    info "Stopping nosleep mode..."
    stop_caffeinate
    restore_pmset
    echo ""
    success "nosleep is OFF. Normal power management restored."
    echo ""
    ;;

  status)
    show_status
    ;;

  help|--help|-h)
    show_help
    ;;

  *)
    error "Unknown command: $1"
    show_help
    exit 1
    ;;
esac
