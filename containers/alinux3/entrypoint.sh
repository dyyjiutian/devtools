#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_SYNC="${DEVTOOLS_USER_SYNC:-${SCRIPT_DIR}/user-sync.sh}"
CONFIG_SYNC="${DEVTOOLS_CONFIG_SYNC:-${SCRIPT_DIR}/config-sync.sh}"
[[ -x "$USER_SYNC" ]] || USER_SYNC=/usr/local/bin/devtools-user-sync
[[ -x "$CONFIG_SYNC" ]] || CONFIG_SYNC=/usr/local/bin/devtools-config-sync
DEV_USER="${DEV_USER:-admin}"
DEV_HOME="${DEV_HOME:-/home/${DEV_USER}}"
DEV_SHELL="${DEV_SHELL:-/bin/zsh}"

usage() {
  cat <<'EOF'
Usage: entrypoint.sh [COMMAND [ARG...]]

The image starts as root, synchronizes the pre-created admin user's UID/GID,
then executes development commands as that user.

Environment:
  DEV_USER              Runtime user name (default: admin)
  DEV_UID               Runtime UID (default: 1000)
  DEV_GID               Runtime GID (default: 1000)
  DEV_HOME              Runtime home (default: /home/<DEV_USER>)
  DEV_SHELL             Runtime shell (default: /bin/zsh)
  DEV_RUN_AS_ROOT       Execute the command as root
  DEV_SKIP_USER_SYNC    Skip UID/GID synchronization (root only)
EOF
}

error() {
  echo "[devtools-entrypoint] ERROR: $*" >&2
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    error "the image entrypoint must start as root; use --user root and DEV_UID/DEV_GID"
    exit 1
  fi
}

detect_workspace_identity() {
  [[ -n "${DEV_UID+x}" || ! -d /workspace ]] && return 0

  local workspace_uid workspace_gid
  workspace_uid="$(stat -c '%u' /workspace 2>/dev/null || true)"
  workspace_gid="$(stat -c '%g' /workspace 2>/dev/null || true)"
  if [[ "$workspace_uid" =~ ^[0-9]+$ && "$workspace_gid" =~ ^[0-9]+$ && "$workspace_uid" != 0 ]]; then
    export DEV_UID="$workspace_uid"
    export DEV_GID="$workspace_gid"
  fi
}

run_as_user() {
  local -a command=("$@")
  if command -v runuser >/dev/null 2>&1; then
    exec runuser --user "$DEV_USER" -- \
      env HOME="$DEV_HOME" USER="$DEV_USER" LOGNAME="$DEV_USER" SHELL="$DEV_SHELL" \
      "${command[@]}"
  fi
  if command -v su >/dev/null 2>&1; then
    exec su -s "$DEV_SHELL" - "$DEV_USER" -c 'exec "$@"' -- "${command[@]}"
  fi
  error "neither runuser nor su is available to drop privileges"
  exit 1
}

start_sshd() {
  [[ -x /usr/sbin/sshd ]] || {
    error "sshd is not installed in this image"
    exit 1
  }
  ssh-keygen -A >/dev/null 2>&1 || true
  exec /usr/sbin/sshd -D -e "$@"
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  require_root
  detect_workspace_identity

  if [[ "${DEV_SKIP_USER_SYNC:-false}" != "true" ]]; then
    DEV_USER="$DEV_USER" \
      DEV_UID="${DEV_UID:-1000}" \
      DEV_GID="${DEV_GID:-1000}" \
      DEV_HOME="$DEV_HOME" \
      DEV_SHELL="$DEV_SHELL" \
      "$USER_SYNC"
  fi

  if [[ -x "$CONFIG_SYNC" && "${DEV_SKIP_CONFIG_SYNC:-false}" != "true" ]]; then
    DEV_USER="$DEV_USER" \
      DEV_UID="${DEV_UID:-1000}" \
      DEV_GID="${DEV_GID:-1000}" \
      DEV_HOME="$DEV_HOME" \
      "$CONFIG_SYNC"
  fi

  if [[ "${1:-}" == "sshd" || "${1:-}" == "/usr/sbin/sshd" ]]; then
    shift
    start_sshd "$@"
  fi

  if [[ "$#" -eq 0 ]]; then
    set -- "$DEV_SHELL" -l
  fi

  if [[ "${DEV_RUN_AS_ROOT:-false}" == "true" ]]; then
    exec env HOME="$DEV_HOME" USER="$DEV_USER" LOGNAME="$DEV_USER" SHELL="$DEV_SHELL" "$@"
  fi

  run_as_user "$@"
}

main "$@"
