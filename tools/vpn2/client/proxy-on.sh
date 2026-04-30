#!/usr/bin/env bash
# 一键开启 macOS 系统代理（等价于 macos-system-proxy.sh on）
exec "$(cd "$(dirname "$0")" && pwd)/macos-system-proxy.sh" on "$@"
