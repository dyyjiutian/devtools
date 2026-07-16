# setproxy 国内测速对象调整实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将国内测速改为清华 TUNA 大文件的固定 10 MB Range 下载，使其与海外 Cloudflare 10 MB 样本可比较。

**Architecture:** 保留现有 `speed_test` 统一测速函数，为其增加一个可选的 curl 请求参数字符串。国内调用传入 `-H "Range: bytes=0-9999999"` 并继续强制直连；海外调用不传额外参数，行为不变。

**Tech Stack:** Bash 3.2+、curl、现有 fake-curl 回归测试。

## Global Constraints

- 国内测速 URL 使用 `https://mirrors.tuna.tsinghua.edu.cn/archlinux/iso/latest/archlinux-x86_64.iso`。
- 国内只下载 `bytes=0-9999999`，即 10,000,000 bytes。
- 国内请求必须继续显式绕过所有代理。
- 海外 Cloudflare 10 MB 测速保持不变。
- 不修改 `~/.ssh/config` 或代理端口配置。

---

### Task 1: 固定国内测速为 TUNA 10 MB Range

**Files:**
- Modify: `tools/vpn/client/setproxy_test.sh`
- Modify: `tools/vpn/client/bin/setproxy`

**Interfaces:**
- Consumes: `speed_test label proxy_arg url [range_header]`
- Produces: 国内 TUNA Range 请求和原有测速输出格式。

- [x] **Step 1: 写入失败回归断言**

在 fake curl 日志检查中加入：

```bash
tuna_call="$(grep 'mirrors.tuna.tsinghua.edu.cn/archlinux/iso/latest/archlinux-x86_64.iso' "${CURL_LOG}" || true)"
[[ "${tuna_call}" == *'<--proxy><><--noproxy><*>'* ]] \
    || fail "domestic TUNA speed test did not explicitly bypass proxies"
[[ "${tuna_call}" == *'<-H><Range: bytes=0-9999999>'* ]] \
    || fail "domestic TUNA speed test did not request a fixed 10 MB range"
if grep -q 'mirrors.aliyun.com/centos' "${CURL_LOG}"; then
    fail "domestic speed test still uses the small Aliyun torrent"
fi
```

- [x] **Step 2: 运行测试确认按预期失败**

Run: `bash tools/vpn/client/setproxy_test.sh`

Expected: FAIL，提示未使用 TUNA 10 MB Range。

- [x] **Step 3: 实现最小修改**

将 `speed_test` 调整为接受可选 Range：

```bash
speed_test() {
    local label="$1" proxy_arg="$2" url="$3" range_header="${4:-}"
    local stats code time_total size speed_bps kbps mbps
    local curl_args=(-sSL --connect-timeout 10 --max-time 30 -o /dev/null \
        -w "%{http_code} %{time_total} %{size_download} %{speed_download}")
    [[ -n "$range_header" ]] && curl_args+=(-H "$range_header")
    stats="$(curl_request "$proxy_arg" "${curl_args[@]}" "$url" 2>/dev/null)" \
        || stats="000 0 0 0"
```

国内调用改为：

```bash
speed_test "国内(直连)   清华 TUNA 10MB :" "" \
    "https://mirrors.tuna.tsinghua.edu.cn/archlinux/iso/latest/archlinux-x86_64.iso" \
    "Range: bytes=0-9999999" || ok=false
```

- [x] **Step 4: 运行完整测试和语法检查**

Run:

```bash
bash tools/vpn/client/setproxy_test.sh
bash -n tools/vpn/client/bin/setproxy tools/vpn/client/install-setproxy.sh tools/vpn/client/setproxy_test.sh
git diff --check
```

Expected: 回归测试 `7/7` 通过，语法及 diff 检查退出码为 0。

- [x] **Step 5: 安装并实际验证**

Run:

```bash
bash tools/vpn/client/install-setproxy.sh
cmp -s tools/vpn/client/bin/setproxy "$HOME/.local/bin/setproxy"
"$HOME/.local/bin/setproxy" test
```

Expected: 国内项显示 `清华 TUNA 10MB` 且下载大小为 `10000000 bytes`。

- [x] **Step 6: 提交**

```bash
git add tools/vpn/client/bin/setproxy tools/vpn/client/setproxy_test.sh
git commit -m "fix: use comparable domestic speed target"
```
