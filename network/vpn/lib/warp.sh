#!/usr/bin/env bash
# =============================================================================
# Cloudflare WARP 安装共享库（exit/setup.sh 与 relay/fallback.sh 共用）
# 约定：调用方须先定义 info/success/warn/error 日志函数，并 set -euo pipefail。
# 测试可 source 使用方脚本（SOURCE_ONLY 门）复用这些 helper，无 root/安装副作用。
# =============================================================================

set -euo pipefail

# Cloudflare WARP 官方 RPM 源使用 $releasever，但目前仅发布 9/10。
# Alibaba Cloud Linux / Anolis 的 VERSION_ID（3/4）会拼成 rpm/3、rpm/4 → 404。
# Alinux 4 有 glibc 2.38：必须用 el9（el10 需要 GLIBC_2.39，装得上也可能跑不了）。
resolve_warp_rpm_releasever() {
    local releasever="${1:-}"
    case "$releasever" in
        9|10) echo "$releasever" ;;
        *) echo "9" ;;
    esac
}

write_cloudflare_warp_repo() {
    local repo_file="${1:-/etc/yum.repos.d/cloudflare-warp.repo}"
    local releasever
    releasever="$(resolve_warp_rpm_releasever "${2:-}")"
    cat >"$repo_file" <<EOF
[cloudflare-warp-stable]
name=cloudflare-warp-stable
baseurl=https://pkg.cloudflareclient.com/rpm/${releasever}
enabled=1
type=rpm
gpgcheck=1
gpgkey=https://pkg.cloudflareclient.com/pubkey.gpg
EOF
}

# 无桌面系统常缺 webkit2gtk3 / libappindicator（仅 GUI 托盘依赖）。
# warp-cli / warp-svc 不链接它们；下载 RPM 后 --nodeps 安装即可。
install_cloudflare_warp_rhel_cli_only() {
    local tmpdir arch rpmfile
    tmpdir="$(mktemp -d)"
    arch="$(uname -m)"

    if command -v dnf >/dev/null 2>&1; then
        dnf install -y 'dnf-command(download)' >/dev/null 2>&1 \
            || dnf install -y dnf-plugins-core >/dev/null 2>&1 \
            || true
        if ! dnf download --arch "${arch}" --destdir "${tmpdir}" cloudflare-warp; then
            rm -rf "${tmpdir}"
            error "dnf download cloudflare-warp 失败"
            return 1
        fi
    else
        yum install -y yum-utils >/dev/null 2>&1 || true
        if ! yumdownloader --destdir "${tmpdir}" "cloudflare-warp.${arch}" \
            && ! yumdownloader --destdir "${tmpdir}" cloudflare-warp; then
            rm -rf "${tmpdir}"
            error "yumdownloader cloudflare-warp 失败"
            return 1
        fi
    fi

    rpmfile="$(find "${tmpdir}" -maxdepth 1 -type f -name 'cloudflare-warp*.rpm' | head -1 || true)"
    if [[ -z "${rpmfile}" ]]; then
        rm -rf "${tmpdir}"
        error "未能下载 cloudflare-warp RPM（arch=${arch}）"
        return 1
    fi
    rpm -Uvh --nodeps "${rpmfile}"
    rm -rf "${tmpdir}"
}

install_cloudflare_warp_rhel() {
    # 先装 warp-svc 实际需要的运行时依赖（忽略已安装）。
    yum install -y ca-certificates dbus desktop-file-utils iproute \
        libpcap nftables nss-tools tpm2-tools >/dev/null 2>&1 || true

    if yum install -y cloudflare-warp; then
        return 0
    fi

    warn "标准 yum 安装失败（常见缺 webkit2gtk3 等 GUI 依赖），改用 CLI-only（rpm --nodeps）"
    install_cloudflare_warp_rhel_cli_only
}

# install_warp <rhel|debian> [version_id]
# 安装 WARP 并设为 proxy 模式（SOCKS5 on 127.0.0.1:40000），不接管系统路由。
install_warp() {
    local os="${1:-}" version_id="${2:-}"
    case "$os" in
        rhel)
            # 幂等覆盖官方模板：避免 Alinux $releasever=4 指向不存在的 rpm/4。
            write_cloudflare_warp_repo /etc/yum.repos.d/cloudflare-warp.repo "$version_id"
            install_cloudflare_warp_rhel
            ;;
        debian)
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
                | gpg --dearmor > /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] \
https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" \
                > /etc/apt/sources.list.d/cloudflare-client.list
            apt-get update -qq && apt-get install -y cloudflare-warp
            ;;
        *)
            error "install_warp: 未知 OS 类型 '${os}'（期望 rhel|debian）"
            return 1
            ;;
    esac
    # 安装后校验二进制可运行：官方 rpm/9、rpm/10 构建要求 GLIBC_2.33/2.34+，
    # Alinux 3 / CentOS 8 系 glibc 2.32 跑不动（见 vpn README Issues 2026-11-18）。
    if ! warp-cli --version >/dev/null 2>&1; then
        error "warp-cli 无法运行（常见：el9/el10 构建要求 GLIBC_2.33+，本机 glibc 过旧）"
        error "修复：从同系统已装好 WARP 的节点拷贝 /bin/warp-{cli,svc,dex} 与 warp-svc.service，或钉住旧版 RPM"
        return 1
    fi
    systemctl enable --now warp-svc
    sleep 2
    warp-cli --accept-tos registration new 2>/dev/null || true
    warp-cli --accept-tos mode proxy
    warp-cli --accept-tos connect
    sleep 3
}

# ensure_warp_connected：已连接则直接返回；否则安装/重连。失败返回 1（调用方决定降级策略）。
ensure_warp_connected() {
    local os="${1:-}" version_id="${2:-}"
    if command -v warp-cli >/dev/null 2>&1 \
        && warp-cli --accept-tos status 2>/dev/null | grep -q "Connected"; then
        return 0
    fi
    if ! command -v warp-cli >/dev/null 2>&1; then
        install_warp "$os" "$version_id"
    else
        warp-cli --accept-tos connect 2>/dev/null || true
        sleep 3
    fi
    warp-cli --accept-tos status 2>/dev/null | grep -q "Connected"
}