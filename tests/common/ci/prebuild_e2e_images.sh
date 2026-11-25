#!/usr/bin/env bash
# Load cached E2E image tarballs, build profiles whose Dockerfile changed,
# and write tarballs back so the next job can skip the mirror download.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RUNNER="$REPO_ROOT/tests/common/docker/run_e2e_in_docker.sh"
CACHE_DIR="${DEVTOOLS_E2E_IMAGE_CACHE:-/tmp/devtools-e2e-images}"

show_help() {
  cat <<EOF
Usage: prebuild_e2e_images.sh [--cache-dir DIR]

Load docker image tarballs from DIR (default /tmp/devtools-e2e-images),
build any E2E profile whose local image does not match its Dockerfile,
and save updated tarballs. The three profiles run in parallel.

EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cache-dir)
      CACHE_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      show_help
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$CACHE_DIR" ]]; then
  echo "prebuild_e2e_images.sh: --cache-dir requires a directory" >&2
  exit 1
fi

mkdir -p "$CACHE_DIR"

image_sha() {
  docker image inspect -f '{{index .Config.Labels "devtools.dockerfile.sha"}}' "$1" 2>/dev/null || true
}

prepare_profile() {
  local profile="$1" tag="$2" tar="$3"
  local before="" after=""
  if [[ -f "$tar" ]]; then
    echo "==> loading $tag from $tar"
    docker load -i "$tar"
  fi
  if docker image inspect "$tag" >/dev/null 2>&1; then
    before="$(image_sha "$tag")"
  fi
  bash "$RUNNER" --profile "$profile" --build-only
  after="$(image_sha "$tag")"
  if [[ ! -f "$tar" || "$before" != "$after" ]]; then
    echo "==> saving $tag to $tar"
    docker save -o "${tar}.tmp" "$tag"
    mv "${tar}.tmp" "$tar"
  else
    echo "==> $tag tarball already matches"
  fi
}

status=0
prepare_profile linux_ubuntu devtools-e2e:ubuntu "$CACHE_DIR/ubuntu.tar" &
pid_ubuntu=$!
prepare_profile linux_alinux3 devtools-e2e:alinux3 "$CACHE_DIR/alinux3.tar" &
pid_alinux3=$!
prepare_profile linux_alinux4 devtools-e2e:alinux4 "$CACHE_DIR/alinux4.tar" &
pid_alinux4=$!
wait "$pid_ubuntu" || status=1
wait "$pid_alinux3" || status=1
wait "$pid_alinux4" || status=1
exit "$status"
