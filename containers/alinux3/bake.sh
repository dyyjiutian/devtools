#!/usr/bin/env bash
# Build alinux3-devbox and map a host-side loopback proxy into the build.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BAKE_FILE="${SCRIPT_DIR}/docker-bake.hcl"

usage() {
  cat <<'EOF'
Usage: bake.sh [OPTION] [-- BAKE_ARG...]

Build the linux/amd64 alinux3-devbox image with docker buildx bake.
Rewrites 127.0.0.1/localhost in HTTP(S)_PROXY to host.docker.internal so
the build container can reach a proxy running on the Docker host.
Aliyun mirrors stay in NO_PROXY and are rewritten to mirrors.aliyun.com
inside the Dockerfile.

The image is tagged alinux3-devbox:YYYYMMDD-HHMM (local time, minute)
and alinux3-devbox:latest. Override with IMAGE_TAG.

Options:
  -h, --help     Show this help
  -n, --dry-run  Print the bake command without running it

Environment:
  HTTP_PROXY / HTTPS_PROXY / NO_PROXY   Host proxy settings (http_proxy aliases work)
  IMAGE_TAG                             Image tag (default: local YYYYMMDD-HHMM)
EOF
}

rewrite_loopback_host() {
  local value="${1:-}"
  value="${value//127.0.0.1/host.docker.internal}"
  value="${value//localhost/host.docker.internal}"
  printf '%s' "$value"
}

join_no_proxy() {
  local extra="localhost,127.0.0.1,::1,mirrors.aliyun.com,.aliyun.com,.aliyuncs.com"
  local current="${1:-}"
  if [[ -z "$current" ]]; then
    printf '%s' "$extra"
    return 0
  fi
  printf '%s,%s' "$current" "$extra"
}

DRY_RUN=false
BAKE_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)    usage; exit 0 ;;
    -n|--dry-run) DRY_RUN=true; shift ;;
    --)           shift; BAKE_ARGS+=("$@"); break ;;
    *)            BAKE_ARGS+=("$1"); shift ;;
  esac
done

HTTP_PROXY_VAL="$(rewrite_loopback_host "${HTTP_PROXY:-${http_proxy:-}}")"
HTTPS_PROXY_VAL="$(rewrite_loopback_host "${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-}}}}")"
NO_PROXY_VAL="$(join_no_proxy "${NO_PROXY:-${no_proxy:-}}")"
IMAGE_TAG="${IMAGE_TAG:-$(date +%Y%m%d-%H%M)}"
export TAG="$IMAGE_TAG"

# Buildx 0.17+ filesystem entitlements: a linked worktree's git dir lives in
# the main checkout, so bake asks to read that path before sending context.
git_common="$(git -C "$SCRIPT_DIR" rev-parse --git-common-dir 2>/dev/null || true)"
if [[ -n "$git_common" && "$git_common" != /* ]]; then
  git_common="$(cd "$SCRIPT_DIR" && cd "$git_common" && pwd)"
fi
main_repo=""
if [[ -n "$git_common" ]]; then
  main_repo="$(cd "$(dirname "$git_common")" && pwd)"
fi

CMD=(
  docker buildx bake -f "$BAKE_FILE" devbox --load
)
if [[ -n "$main_repo" ]]; then
  CMD+=(--allow "fs.read=${main_repo}")
fi
CMD+=(
  --set "devbox.context=${REPO_ROOT}"
  --set "devbox.args.HTTP_PROXY=${HTTP_PROXY_VAL}"
  --set "devbox.args.HTTPS_PROXY=${HTTPS_PROXY_VAL}"
  --set "devbox.args.NO_PROXY=${NO_PROXY_VAL}"
  --set "devbox.args.http_proxy=${HTTP_PROXY_VAL}"
  --set "devbox.args.https_proxy=${HTTPS_PROXY_VAL}"
  --set "devbox.args.no_proxy=${NO_PROXY_VAL}"
)
if [[ ${#BAKE_ARGS[@]} -gt 0 ]]; then
  CMD+=("${BAKE_ARGS[@]}")
fi

if [[ "$DRY_RUN" == "true" ]]; then
  printf 'TAG=%q ' "$IMAGE_TAG"
  printf '%q ' "${CMD[@]}"
  printf '\n'
  exit 0
fi

# Keep the client on 127.0.0.1 (host.docker.internal is only valid inside the
# build). Rewritten values are passed as Dockerfile build-args only.
exec "${CMD[@]}"
