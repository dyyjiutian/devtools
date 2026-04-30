#!/usr/bin/env bash
# 一键关闭 macOS 系统代理（等价于 macos-system-proxy.sh off）
exec "$(cd "$(dirname "$0")" && pwd)/macos-system-proxy.sh" off "$@"
