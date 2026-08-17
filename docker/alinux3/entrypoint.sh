#!/usr/bin/env bash
# Root entrypoint for alinux3-devbox. Starts dockerd when privileged, then
# drops to admin. Without privilege, warn and still open an admin shell.
# Does not expose an unencrypted TCP Docker port.

set -euo pipefail

DEVBOX_USER="${DEVBOX_USER:-admin}"
DOCKERD_LOG="${DOCKERD_LOG:-/var/log/dockerd.log}"
DOCKERD_TIMEOUT="${DOCKERD_TIMEOUT:-30}"

usage() {
  cat <<'EOF'
Usage: entrypoint.sh [COMMAND...]

Root entrypoint for alinux3-devbox:
  - When running as root with --privileged, start dockerd on the unix socket
    (overlay2, falling back to vfs) and wait until docker info succeeds.
  - Then drop to admin (or $DEVBOX_USER) and exec the given command.
  - Without --privileged, print a warning and still drop to admin.
  - If already running as a non-root user, exec the command directly.

Default command is bash. Typical run:

  docker run --privileged --rm -it alinux3-devbox:latest

Options:
  -h, --help  Show this help
EOF
}

info() { echo -e "\033[34m[INFO]\033[0m $1"; }
warn() { echo -e "\033[33m[WARN]\033[0m $1" >&2; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -eq 0 ]]; then
  set -- bash
fi

is_privileged() {
  local dir
  dir="$(mktemp -d /tmp/dind-probe.XXXXXX 2>/dev/null || true)"
  [[ -n "$dir" ]] || return 1
  if mount -t tmpfs -o size=1k tmpfs "$dir" >/dev/null 2>&1; then
    umount "$dir" >/dev/null 2>&1 || true
    rmdir "$dir" >/dev/null 2>&1 || true
    return 0
  fi
  rmdir "$dir" >/dev/null 2>&1 || true
  return 1
}

wait_for_docker() {
  local i=0
  while [[ "$i" -lt "$DOCKERD_TIMEOUT" ]]; do
    if docker info >/dev/null 2>&1; then
      return 0
    fi
    if ! pgrep -x dockerd >/dev/null 2>&1; then
      return 1
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

stop_dockerd() {
  local pid
  for pid in $(pgrep -x dockerd 2>/dev/null || true); do
    kill "$pid" 2>/dev/null || true
  done
  # overlay2 may leave containerd children; vfs retry needs a clean graph dir.
  for pid in $(pgrep -x containerd 2>/dev/null || true); do
    kill "$pid" 2>/dev/null || true
  done
  sleep 1
}

launch_dockerd() {
  local driver="$1"
  mkdir -p /var/lib/docker /var/run /var/log
  touch "$DOCKERD_LOG"
  # Privileged DinD: unix socket only. Prefer overlay2; vfs works under qemu.
  dockerd \
    --host=unix:///var/run/docker.sock \
    --storage-driver="$driver" \
    --exec-opt native.cgroupdriver=cgroupfs \
    >>"$DOCKERD_LOG" 2>&1 &
  if wait_for_docker; then
    info "dockerd is ready (unix:///var/run/docker.sock, ${driver})"
    return 0
  fi
  return 1
}

start_dockerd() {
  if ! command -v dockerd >/dev/null 2>&1; then
    warn "dockerd is not installed"
    return 1
  fi
  if ! is_privileged; then
    warn "container is not privileged; inner dockerd will not start"
    warn "re-run with: docker run --privileged --rm -it alinux3-devbox:latest"
    return 1
  fi

  if launch_dockerd overlay2; then
    return 0
  fi

  warn "overlay2 is unavailable; falling back to vfs"
  stop_dockerd
  rm -rf /var/lib/docker
  if launch_dockerd vfs; then
    return 0
  fi

  warn "dockerd did not become ready in ${DOCKERD_TIMEOUT}s; docker CLI will not work"
  warn "re-run with: docker run --privileged --rm -it alinux3-devbox:latest"
  if [[ -s "$DOCKERD_LOG" ]]; then
    tail -n 20 "$DOCKERD_LOG" >&2 || true
  fi
  return 1
}

drop_to_user() {
  local user="$1"
  shift
  if ! command -v runuser >/dev/null 2>&1; then
    warn "runuser not found; exec as current user"
    exec "$@"
  fi
  exec runuser -u "$user" -- env HOME="/home/${user}" USER="$user" LOGNAME="$user" "$@"
}

if [[ "$(id -u)" -eq 0 ]]; then
  if start_dockerd; then
    :
  else
    warn "inner dockerd is unavailable (need --privileged for DinD)"
  fi
  drop_to_user "$DEVBOX_USER" "$@"
fi

exec "$@"
