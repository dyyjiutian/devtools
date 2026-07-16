#!/usr/bin/env bash

set -euo pipefail

DEV_USER="${DEV_USER:-admin}"
DEV_UID="${DEV_UID:-1000}"
DEV_GID="${DEV_GID:-1000}"
DEV_HOME="${DEV_HOME:-/home/${DEV_USER}}"
DEV_SHELL="${DEV_SHELL:-/bin/zsh}"

info() {
  echo "[devtools-user] $*"
}

error() {
  echo "[devtools-user] ERROR: $*" >&2
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    error "runtime user synchronization requires root"
    return 1
  fi
}

validate_identity() {
  [[ "$DEV_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || {
    error "invalid DEV_USER: ${DEV_USER}"
    return 1
  }
  [[ "$DEV_UID" =~ ^[0-9]+$ ]] || {
    error "invalid DEV_UID: ${DEV_UID}"
    return 1
  }
  [[ "$DEV_GID" =~ ^[0-9]+$ ]] || {
    error "invalid DEV_GID: ${DEV_GID}"
    return 1
  }
  if (( DEV_UID == 0 || DEV_GID == 0 )); then
    error "DEV_UID and DEV_GID must be non-root values"
    return 1
  fi
  if (( DEV_UID > 2147483647 || DEV_GID > 2147483647 )); then
    error "DEV_UID and DEV_GID exceed the supported range"
    return 1
  fi
  [[ -x "$DEV_SHELL" ]] || {
    error "shell does not exist or is not executable: ${DEV_SHELL}"
    return 1
  }
}

lookup_passwd_by_uid() {
  getent passwd "$1" 2>/dev/null | cut -d: -f1
}

lookup_group_by_gid() {
  getent group "$1" 2>/dev/null | cut -d: -f1
}

ensure_user() {
  local existing_uid existing_gid current_group target_group

  existing_uid="$(id -u "$DEV_USER" 2>/dev/null || true)"
  if [[ -z "$existing_uid" ]]; then
    local occupied_user
    occupied_user="$(lookup_passwd_by_uid "$DEV_UID" || true)"
    if [[ -n "$occupied_user" && "$occupied_user" != "$DEV_USER" ]]; then
      error "UID ${DEV_UID} is already used by ${occupied_user}; refusing to modify it"
      return 1
    fi

    target_group="$(lookup_group_by_gid "$DEV_GID" || true)"
    if [[ -z "$target_group" ]]; then
      groupadd --gid "$DEV_GID" "$DEV_USER"
      target_group="$DEV_USER"
    fi

    useradd \
      --uid "$DEV_UID" \
      --gid "$DEV_GID" \
      --create-home \
      --home-dir "$DEV_HOME" \
      --shell "$DEV_SHELL" \
      "$DEV_USER"
    info "created ${DEV_USER}:${DEV_UID}:${DEV_GID}"
    return 0
  fi

  existing_gid="$(id -g "$DEV_USER")"
  current_group="$(id -gn "$DEV_USER")"

  if [[ "$existing_uid" != "$DEV_UID" ]]; then
    local occupied_user
    occupied_user="$(lookup_passwd_by_uid "$DEV_UID" || true)"
    if [[ -n "$occupied_user" && "$occupied_user" != "$DEV_USER" ]]; then
      error "UID ${DEV_UID} is already used by ${occupied_user}; refusing to modify it"
      return 1
    fi
    usermod --uid "$DEV_UID" "$DEV_USER"
  fi

  if [[ "$existing_gid" != "$DEV_GID" ]]; then
    target_group="$(lookup_group_by_gid "$DEV_GID" || true)"
    if [[ -z "$target_group" ]]; then
      groupmod --gid "$DEV_GID" "$current_group"
    fi
    usermod --gid "$DEV_GID" "$DEV_USER"
  fi

  usermod --home "$DEV_HOME" --shell "$DEV_SHELL" "$DEV_USER"
  mkdir -p "$DEV_HOME"
  chown -R "$DEV_UID:$DEV_GID" "$DEV_HOME"
  info "synchronized ${DEV_USER}:${DEV_UID}:${DEV_GID}"
}

main() {
  require_root
  validate_identity
  ensure_user
}

main "$@"
