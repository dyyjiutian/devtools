#!/usr/bin/env bash
# 一键开启代理（macOS：系统代理；Linux：终端环境变量）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ "$(uname)" == "Darwin" ]]; then
    exec "${SCRIPT_DIR}/macos-system-proxy.sh" on "$@"
else
    exec "${SCRIPT_DIR}/linux-shell-proxy.sh" on "$@"
fi
