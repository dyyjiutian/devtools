# VPN 出口节点

在出口服务器部署 Xray VLESS + Reality 服务，并管理用户配置。

~~~bash
sudo bash network/vpn/exit/setup.sh --help
bash network/vpn/exit/manage.sh --help
bash network/vpn/exit/setup_test.sh
~~~

脚本会修改系统服务、端口和防火墙配置（含 Cloudflare WARP）。网络与防火墙变更前请确认目标主机与回滚方式。

## Issues

### 2026-08-08 — 新增用户后全员流量被重新计费

**表象：** `manage.sh add`（以及 `remove` / `sync` / 超限踢人）后，已有用户的用量从 0 重新累计，配额等于重新开始。

**根因：** 上述操作通过 `systemctl restart xray` 应用 clients；Xray Stats API 计数仅存在进程内存，重启即丢失。

**解法：** 重载前把各用户当前 session 用量写入 `/var/lib/vpn-exit/traffic.tsv`；展示与配额使用「持久化累计 + 当前 session」。仅 `reset-stats`（含每月 1 日 cron）清零。回归：`bash network/vpn/exit/manage_test.sh`。

### 2026-08-04 — Alibaba Cloud Linux 4 上 Cloudflare WARP 安装失败（源 404 / 缺 webkit2gtk3）

**表象：** `exit/setup.sh` 安装 WARP 时失败，先后可能出现：

```text
Status code: 404 for https://pkg.cloudflareclient.com/rpm/4/repodata/repomd.xml
nothing provides webkit2gtk3 needed by cloudflare-warp-...el9.x86_64
```

**根因：**
1. 官方 repo 使用 `$releasever`；Alinux 4 会拼成不存在的 `rpm/4`。
2. pin 到 `rpm/9` 后，RPM 仍声明 GUI 依赖 `webkit2gtk3`，Alinux 4 只提供 `webkit2gtk4.1`。`warp-cli` / `warp-svc` 并不链接 WebKit。
3. 不能改用 `rpm/10`：el10 二进制需要 `GLIBC_2.39`，Alinux 4 为 glibc 2.38。

**解法：** 幂等写入 pin 到 `rpm/9` 的 repo；`yum install` 失败时回退下载 RPM 并以 `rpm -Uvh --nodeps` 做 CLI-only 安装。重新执行 `sudo ./exit/setup.sh` 即可。
