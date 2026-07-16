# setproxy 国内测速对象调整设计

## 目标

将 `setproxy test` 的国内测速从约 389 KB 的阿里云 `.torrent` 文件，调整为与海外测速相同的固定 10 MB 下载样本，使两项吞吐结果更具可比性。

## 方案

- 国内测速对象使用清华大学 TUNA Arch Linux 最新版 ISO：
  `https://mirrors.tuna.tsinghua.edu.cn/archlinux/iso/latest/archlinux-x86_64.iso`
- 请求增加 HTTP Range：`bytes=0-9999999`，只下载前 10,000,000 bytes。
- 国内请求继续使用 `--proxy '' --noproxy '*'` 强制直连。
- 海外 Cloudflare 10 MB 测速保持不变。
- `speed_test` 增加可选 Range 参数；未提供时维持当前行为。

## 验证

回归测试必须确认：

- 国内测速请求命中 TUNA URL。
- 请求包含 `Range: bytes=0-9999999`。
- 国内请求继续显式绕过代理。
- 不再请求旧的阿里云 `.torrent` 文件。
- 完整回归测试和 shell 语法检查通过。
