#!/usr/bin/env bash
# 运行 os/macos 的 Bats 测试。
# - Bazel：bazel test //os/macos:macos_setup_bats_test（使用 runfiles 里的 bats-core）
# - 本地：在仓库中执行 ./run_bats.sh，需已安装 bats（如 brew install bats-core）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# SCRIPT_DIR = <repo或runfiles>/<ws>/os/macos
WS_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNFILES_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

export SETUP_SH="${WS_ROOT}/os/macos/setup.sh"
SETUP_BATS="${WS_ROOT}/os/macos/setup.bats"

BATS_BIN=""
BATS_ROOT=""
for d in \
  "${RUNFILES_ROOT}/bats_core" \
  "${RUNFILES_ROOT}/+http_archive+bats_core"; do
  if [[ -f "${d}/bin/bats" ]]; then
    BATS_ROOT="$d"
    BATS_BIN="${d}/bin/bats"
    break
  fi
done
if [[ -z "${BATS_BIN}" ]]; then
  while IFS= read -r b; do
    BATS_ROOT="$(cd "$(dirname "$b")/.." && pwd)"
    BATS_BIN="$b"
    break
  done < <(find "${RUNFILES_ROOT}" -maxdepth 4 -path '*/bin/bats' -type f 2>/dev/null || true)
fi

# 非 Bazel runfiles：RUNFILES_ROOT 往往是仓库的父目录，上面找不到 bats → 用 PATH
if [[ -z "${BATS_BIN}" || ! -x "${BATS_BIN}" ]]; then
  if command -v bats &>/dev/null; then
    BATS_BIN="$(command -v bats)"
    BATS_ROOT=""
  fi
fi

if [[ -n "${BATS_ROOT}" ]]; then
  export BATS_ROOT
fi

if [[ ! -f "${SETUP_SH}" ]]; then
  echo "run_bats.sh: setup.sh not found at ${SETUP_SH}" >&2
  exit 1
fi
if [[ -z "${BATS_BIN}" ]]; then
  echo "run_bats.sh: 未找到 bats。请安装: brew install bats-core，或使用: bazel test //os/macos:macos_setup_bats_test" >&2
  exit 1
fi

exec bash "${BATS_BIN}" "${SETUP_BATS}"
