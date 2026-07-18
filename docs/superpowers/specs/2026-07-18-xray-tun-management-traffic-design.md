# Xray Linux TUN 管理流量保护设计

## 背景

Linux 客户端的 TUN 路由辅助脚本当前添加了：

```text
uidrange 0-4294967294 lookup 1001
```

这会把服务器上几乎所有本机发出的流量导入 `xray0`。远程 ECS 的 SSH 回包和 ICMP echo reply 也会被导入 TUN，导致执行安装的 SSH 会话断开，外部 ping 也可能失去响应。

仅绕过当前 SSH 来源 IP 不能满足需求，因为更换 SSH 客户端后仍可能发生同样的问题。需要保护的是入站连接的回包行为。

## 目标

1. 远程任意客户端发起的 SSH 连接都保持原有主路由行为，不依赖固定来源 IP。
2. 远程 IPv4/IPv6 ping 都保持正常回包路径；安全组或本机防火墙的放行策略仍由用户负责。
3. 其他从外部进入服务器的新连接，其回包也默认走主路由，避免破坏已有服务。
4. 服务器主动发起且未被连接标记保护的流量继续使用现有 TUN 分流逻辑。
5. TUN 路由启用前先完成并验证管理流量保护；保护机制不可用时拒绝启用 TUN，不能进入半配置状态。
6. 重复执行、服务停止、服务重启和异常失败都能清理本工具创建的防火墙标记规则、策略路由和 `rp_filter` 修改。

## 非目标

- 不修改阿里云安全组、云防火墙或系统默认 SSH 端口。
- 不通过固定来源 IP 白名单实现保护。
- 不改变普通 SOCKS5/HTTP 代理模式。
- 不接管 Docker、虚拟机或转发流量；现有 TUN 设计仍只处理宿主机本地流量。

## 方案

### 连接级防护

在 TUN 策略路由建立前安装独立、可删除的 netfilter 规则：

- 在物理接口进入的 `NEW` 连接上设置连接标记 `255`；来自 `xray0` 的流量不标记，避免回环。
- 在本机输出链恢复连接标记到 packet mark `255`。
- 对 IPv4/IPv6 ICMP `echo-reply` 额外直接恢复 packet mark `255`，即使 ICMP 连接跟踪状态异常也不把 ping 回包送进 TUN。
- 现有 `ip rule priority 10000 fwmark 255 lookup main` 使这些回包走主路由，绕过 `table 1001`。
- 使用独立 nftables 表；没有 nftables 时使用等价的 IPv4/IPv6 iptables mangle 链。
- nftables 和 iptables 都不可用或规则安装/验证失败时，返回失败并清理已创建的所有状态。

这种方式按连接动态工作：任何新 SSH 客户端、任何新 ping 对端都能获得同样的保护，不依赖安装时的 `SSH_CONNECTION`。

### 启停顺序

`routes_up` 的顺序调整为：

1. 等待 `xray0`、获取 Xray UID、检查策略规则和路由表占用。
2. 保存并修改 `rp_filter`。
3. 安装并验证连接标记规则。
4. 安装 IPv4/IPv6 TUN 路由和策略规则。
5. 任一步失败，按反向顺序清理防火墙规则、策略路由和 `rp_filter`。

`routes_down` 先删除策略路由，再删除本工具拥有的防火墙规则，最后恢复 `rp_filter`；这样停止期间已有连接仍可先回到主路由。清理操作保持幂等，并且不 flush 用户已有的其他防火墙表、链或策略规则。

### 适配器边界

在 `bin/xray-tun-route` 中增加防火墙适配函数，而不是把 nftables/iptables 命令散落在路由编排中：

- `detect_firewall_backend`：优先选择 `nft`，否则选择成对的 `iptables`/`ip6tables`。
- `firewall_up`：创建本工具独立的规则集并完成最小验证。
- `firewall_down`：只删除本工具创建的规则集。
- 通过环境变量允许测试注入命令路径，不改变生产默认命令。

## 错误处理

- 防火墙后端缺失、内核模块/扩展不可用、规则冲突或验证失败时，TUN 服务启动失败。
- 防火墙规则已经安装但后续 IPv4/IPv6 路由失败时，必须先删除防火墙规则，再恢复已修改的 sysctl。
- IPv6 路由仍可按现有策略作为可选能力；但 IPv6 管理连接保护规则安装失败时不能静默继续。
- 清理时即使 Xray 已停止或动态 UID 已不存在，也必须尝试删除防火墙规则、mark 规则和 TUN 路由。
- 错误日志明确指出使用的后端和建议的 `systemctl/journalctl` 检查命令，不打印 VLESS UUID、私钥或其他敏感配置。

## 测试

扩展 `linux_setup_test.sh` 的 fake 命令测试：

1. 验证 TUN 启动先安装并验证连接标记规则，再添加 `uidrange` 策略路由。
2. 验证规则包含 IPv4/IPv6 入站新连接标记、xray0 排除和输出 mark 恢复语义。
3. 验证重复 `up` 不产生重复规则，`down` 只删除本工具规则。
4. 验证 nftables 后端不可用时回退到 iptables；两者都不可用时启动失败且不添加 TUN 路由。
5. 验证防火墙规则安装成功、策略路由失败时，防火墙规则和 `rp_filter` 均恢复。
6. 保留并运行现有 TUN 配置、等待 xray0、规则优先级冲突和生命周期测试。

## 验收标准

- 在 fake netfilter 环境中，测试能证明任意入站连接的回包使用 mark 255/main 路由，而非依赖某个来源 IP。
- `bash -n`、`bash linux_setup_test.sh` 和 `git diff --check` 通过。
- 未启用 `--tun` 的配置和服务行为不变。
- 文档说明远程 ECS 使用 TUN 的安全边界、回滚命令及安全组限制。
