# VPN 中继节点

杭州中继（198.51.100.10）连接客户端与东京出口（198.51.100.20）。
主链路为纯 iptables DNAT 转发，不运行代理软件；可选 WARP 自动兜底应对出口被墙。

## 主链路部署

~~~bash
sudo bash network/vpn/relay/setup.sh --help
sudo bash network/vpn/relay/setup.sh --exit-ip=198.51.100.20
~~~

内容：内核优化（ip_forward + BBR + conntrack + route_localnet）、清扫同端口历史
DNAT 残留（保留 Docker 链）、PREROUTING DNAT + POSTROUTING MASQUERADE + FORWARD 放行、
本机 OUTPUT hairpin（本机客户端与外部终端同路径）、规则持久化。

执行前确认出口地址、监听端口、iptables 规则和回滚方式（`--clean`）。

## WARP 自动兜底（fallback.sh）

~~~bash
sudo bash network/vpn/relay/fallback.sh --help
sudo bash network/vpn/relay/fallback.sh install \
  --exit-ip=198.51.100.20 --exit-ssh=dev.user@198.51.100.20 --sudo-pass-file=<pass>
sudo bash network/vpn/relay/fallback.sh status
sudo bash network/vpn/relay/fallback.sh switch fallback   # 演练
sudo bash network/vpn/relay/fallback.sh switch main
sudo bash network/vpn/relay/fallback.sh clean             # 回滚
~~~

- 组件：Cloudflare WARP（proxy 模式 SOCKS5 40000）、备用 xray（127.0.0.1:8443，
  复用出口 Reality 凭据，客户端零改动）、健康检查 timer（60s）。
- 切换：连续 3 次探测出口 443 失败 → DNAT 切备用 xray→WARP；连续 3 次成功 → 切回。
  备用 xray 平时 enabled 但不运行；兜底期间 WARP 掉线自动重连。
- 备用 xray 路由：私网 block、国内 direct、其余 WARP。
- 凭据安全：Reality 私钥经 SSH 从出口提取，仅写 root:600 文件，输出/日志不含密钥。
- 日志：`/var/log/vpn-relay-fallback.log`；状态：`/var/lib/vpn-relay-fallback/state.json`；
  配置：`/etc/vpn-relay-fallback.conf`。
- 前提：先跑 `setup.sh`（route_localnet 与主路 DNAT）；需要 python3、iptables、systemd。

## 测试

~~~bash
bazel test //network/vpn/relay:setup_test //network/vpn/relay:fallback_test
~~~

L1 source-only / fixture 回归：内核参数文本、历史 DNAT 解析、公网 IP 判定、
状态机阈值切换、凭据校验、备用配置生成与密钥不外泄。