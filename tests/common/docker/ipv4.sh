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

file_sha256() {
  local file="$1" bin
  for bin in sha256sum /usr/bin/sha256sum /bin/sha256sum; do
    if command -v "$bin" >/dev/null 2>&1 || [[ -x "$bin" ]]; then
      "$bin" "$file" | awk '{print $1}'
      return 0
    fi
  done
  for bin in shasum /usr/bin/shasum; do
    if command -v "$bin" >/dev/null 2>&1 || [[ -x "$bin" ]]; then
      "$bin" -a 256 "$file" | awk '{print $1}'
      return 0
    fi
  done
  echo "ipv4.sh: sha256sum or shasum is required" >&2
  return 1
}

# True when the local amd64 image was built from this exact Dockerfile.
image_matches_dockerfile() {
  local image="$1" dockerfile="$2" want="" have=""
  want="$(file_sha256 "$dockerfile")" || return 1
  docker_image_present "$image" || return 1
  docker_image_is_amd64 "$image" || return 1
  have="$(docker image inspect -f '{{index .Config.Labels "devtools.dockerfile.sha"}}' "$image" 2>/dev/null || true)"
  [[ -n "$want" && "$have" == "$want" ]]
}

# Copy Dockerfile into build_ctx. Stage a referenced kernel-headers RPM from
# cache/binaries so the build does not download it.
stage_e2e_dockerfile() {
  local dockerfile_src="$1" build_ctx="$2" repo_root="$3"
  local name="" rpm=""
  cp -L "$dockerfile_src" "$build_ctx/Dockerfile"
  name="$(grep -oE 'kernel-headers-[^[:space:]]+\.x86_64\.rpm' "$build_ctx/Dockerfile" | head -n 1 || true)"
  if [[ -z "$name" ]]; then
    return 0
  fi
  rpm="${repo_root}/cache/binaries/${name}"
  if [[ ! -f "$rpm" ]]; then
    echo "ipv4.sh: missing ${rpm} (run: bash cache/download.sh linux)" >&2
    return 1
  fi
  cp -L "$rpm" "${build_ctx}/${name}"
}
