#!/usr/bin/env bash
# IPv4-first Docker pull/build helpers (Bash 3.2).
# Docker Hub AAAA is often blackholed; BuildKit then hangs on auth.docker.io.
# shellcheck shell=bash

dockerfile_from_image() {
  awk '/^FROM / { print $2; exit }' "$1"
}

docker_hub_ipv4_mirror() {
  case "$1" in
    ubuntu:*|library/ubuntu:*|docker.io/library/ubuntu:*)
      printf '%s\n' "docker.m.daocloud.io/library/ubuntu:${1##*:}"
      ;;
    *)
      return 1
      ;;
  esac
}

docker_image_present() {
  docker image inspect "$1" >/dev/null 2>&1
}

docker_image_is_amd64() {
  local arch
  arch="$(docker image inspect -f '{{.Architecture}}' "$1" 2>/dev/null || true)"
  [[ "$arch" == "amd64" ]]
}

docker_pull_ipv4() {
  local image="$1" mirror=""
  echo "==> pulling $image (IPv4-first; avoid Docker Hub AAAA hang)"
  if docker pull --platform linux/amd64 "$image"; then
    return 0
  fi
  if mirror="$(docker_hub_ipv4_mirror "$image")"; then
    echo "==> official pull failed; retrying IPv4 mirror $mirror"
    docker pull --platform linux/amd64 "$mirror" && docker tag "$mirror" "$image"
    return $?
  fi
  return 1
}

ensure_dockerfile_from_local() {
  local dockerfile="$1" from=""
  from="$(dockerfile_from_image "$dockerfile")"
  [[ -n "$from" ]] || return 0
  if docker_image_present "$from" && docker_image_is_amd64 "$from"; then
    echo "==> using local amd64 base $from"
    return 0
  fi
  docker_pull_ipv4 "$from"
}

# Rewrite FROM to a local name so BuildKit does not contact docker.io (AAAA).
pin_dockerfile_from_local() {
  local df="$1" from="" local_tag="" tmp=""
  from="$(dockerfile_from_image "$df")"
  [[ -n "$from" ]] || return 0
  ensure_dockerfile_from_local "$df" || return 1
  local_tag="devtools-local-from-$(printf '%s' "$from" | tr '/:' '-')"
  docker tag "$from" "$local_tag"
  tmp="$(mktemp)"
  awk -v img="$local_tag" 'NR==1 && $1=="FROM" { print "FROM " img; next } { print }' "$df" >"$tmp"
  mv "$tmp" "$df"
}

docker_build_ipv4() {
  local dockerfile="$1"
  shift
  pin_dockerfile_from_local "$dockerfile" || return 1
  docker build --pull=false --platform linux/amd64 "$@"
}
