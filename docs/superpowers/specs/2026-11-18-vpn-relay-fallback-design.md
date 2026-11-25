# VPN 中继重建：多 SNI + 出口白名单 + WARP 自动兜底

日期：2026-11-18 ｜ 模式：full ｜ 状态：已确认（用户批准开工）

## 目标

旧东京出口 EIP 198.51.100.22 被 GFW 方向性封禁（境外全通、国内 TCP 全断、ICMP 正常）。
用户已为同一台出口 ECS 更换新 EIP **198.51.100.21**（密钥/UUID 经哈希比对与运行配置完全一致，
4 个用户 user1/devuser/guest/beaver 不变）。按上一轮会话确认的方案重建三段式链路：

```
终端（PC/手机/本机/远端 198.51.100.40）
  │ VLESS+Reality，地址统一 198.51.100.10:443
  ▼
杭州中继 = 本地开发机（198.51.100.10）
  主路：纯 iptables DNAT → 198.51.100.21:443（无代理软件参与）
  兜底：健康检查失败自动 DNAT → 本机备用 xray(127.0.0.1:8443) → WARP(CF)
  ▼
东京出口 198.51.100.21：Reality 多 SNI + 443 白名单（仅中继 IP）+ anthropic→WARP（已有）
```

同时在 `network/vpn/README.md` `## Issues` 记录运营商封禁事件。

## 决策摘要

| 决策 | 结论 |
|---|---|
| 兜底切换 | 自动：systemd timer 每 60s 探测出口 443，连续 3 次失败切 WARP，连续 3 次成功切回 |
| 兜底透明性 | 备用 xray 复用出口同一套 Reality 私钥/shortId/clients/serverNames，客户端零改动 |
| 出口白名单 | iptables INPUT 仅放行 198.51.100.10 → 443，其余 DROP；SSH 22 不受影响 |
| 多 SNI | 实测握手体积筛选（openssl -msg 统计服务端握手字节）：icloud 3717B / apple 3715B / cloudflare 2818B / tesla 3286B，全部 TLS1.3+H2、零 ticket；排除 Microsoft（6371B，历史断连根因）、yahoo.co.jp（5542B+边缘节点证书轮换）、amazon/samsung/mozilla（>4.6KB）、amd（H2 INTERNAL_ERROR） |
| dest | 保持 www.icloud.com:443（serverNames 首位，现有客户端兼容） |
| 客户端 | 本机 + 远端 198.51.100.40 重配为中继地址；本机走自身公网 IP + OUTPUT DNAT（hairpin），与外部终端共用同一条切换路径 |
| 实施方式 | 改仓库脚本 → L1 测试 → 用脚本部署（脚本即事实源），不做一次性手工配置 |

## 方案 / 边界

### 1. `network/vpn/lib/warp.sh`（新增，共享库）

把 `exit/setup.sh` 中 5 个 WARP 安装 helper（resolve_warp_rpm_releasever /
write_cloudflare_warp_repo / install_cloudflare_warp_rhel_cli_only /
install_cloudflare_warp_rhel / install_warp）原样移入；`install_warp` 改为接收 OS 参数。
exit 与 relay/fallback 均 source 此库，避免复制逻辑。
`EXIT_SETUP_SOURCE_ONLY=true` 时函数仍可见（现有测试依赖）。
E2E filegroup `vpn_pair_files` 增加该库，保证 compose 容器内相对路径 `../lib/warp.sh` 成立。

### 2. `exit/setup.sh`：多 SNI + 白名单

- `--sni=LIST`（逗号分隔）；默认 `www.icloud.com,www.apple.com,www.cloudflare.com,www.tesla.com`。
  域名格式校验 + 去重；dest = 首个 SNI:443；`serverNames` 写为 JSON 数组。
- 缓存 `/root/.vpn_exit_config`：保留 `REALITY_SNI`（首位，manage.sh 兼容）+ 新增
  `REALITY_SNIS`、`ALLOW_IPS`。加载优先级：CLI > 缓存 REALITY_SNIS > 缓存 REALITY_SNI。
- `--allow-ip=LIST`：iptables INPUT 追加带 `--comment vpn-exit-allow` 标记的
  「443 放行指定 IP」+「443 其余 DROP」规则；`-C` 幂等；重跑先按标记清除旧规则再重建。
  不触碰 22 端口与其他链。firewalld 活跃时改用 rich rule；IPv6 监听时同步 ip6tables。
  `--allow-ip-off` 按标记移除。持久化沿用发行版机制（RHEL iptables-services）。
- VLESS 链接输出 sni=首位，附可选 SNI 列表说明。
- 重跑安全性已验证：出口缓存与运行配置 4 用户 UUID/私钥/sid 哈希全一致。

### 3. `relay/setup.sh`：内核增强 + 规则治理

- sysctl 增补（`/etc/sysctl.d/99-vpn-relay.conf`）：
  `net.ipv4.conf.all.route_localnet=1`（兜底 DNAT 到 127.0.0.1 必需）；
  conntrack：`nf_conntrack_max=262144`、`tcp_timeout_established=3600`、
  `time_wait/close_wait/fin_wait/syn_sent/syn_recv=30`、`udp_timeout=60`、`icmp_timeout=15`；
  hashsize 运行时写 `/sys/module/nf_conntrack/parameters/hashsize`（若存在）。
  sysctl 前先 `modprobe nf_conntrack`，`sysctl -p` 失败降级 warn（容器兼容）。
- **旧规则清扫**（现网实测残留：DNAT 443→198.51.100.23、MASQUERADE→198.51.100.30/198.51.100.23）：
  部署前枚举 PREROUTING 中 `--dport LISTEN_PORT` 的全部 DNAT 规则（不限目标），
  逐条删除并连带删除对应目标的 POSTROUTING MASQUERADE 与 FORWARD 规则；
  保留 Docker 链。新规则统一带 `--comment vpn-relay` 标记，`--clean` 按标记+端口清扫。
- 新增 OUTPUT hairpin：`-t nat -A OUTPUT -d RELAY_IP/32 -p tcp --dport LISTEN_PORT -j DNAT`
  （仅当 RELAY_IP 为公网 IP；本机客户端与外部终端同路径）。
- 默认出口 IP 198.51.100.30 → 198.51.100.21；注释/帮助文案新加坡→东京。
- 增加 `RELAY_SETUP_SOURCE_ONLY` 测试门（与 exit 同约定）。

### 4. `relay/fallback.sh`（新增，兜底子系统）

子命令：`install | check | status | switch <main|fallback> | clean`。
参数：`--exit-ip= --exit-port=443 --listen-port=443 --fallback-port=8443
--exit-ssh=user@host --sudo-pass-file=FILE --threshold=3 --dry-run --help`。

- install：装 WARP（source lib，proxy 模式 SOCKS 40000）→ 经 SSH 从出口安全提取
  Reality 凭据（远端 sudo 读 config，JSON 直写本地 `/usr/local/etc/xray-relay-fallback/reality.json`
  chmod 600，全程不回显）→ 生成备用 xray 配置（inbound 127.0.0.1:8443 同凭据；
  路由 geoip:private→block、geoip:cn/geosite:cn→direct、其余→warp；geo 数据复用
  `/usr/local/share/xray/`）→ `xray run -test` 校验 → systemd 服务 enabled但平时不运行 →
  健康检查 timer（60s）enabled+started → 状态文件 `/var/lib/vpn-relay-fallback/state.json`。
- check：TCP 探测出口 443（timeout 5 bash /dev/tcp）。main 模式连续失败≥threshold →
  确保 WARP Connected（必要时重连）→ 启动备用 xray 并等待端口就绪 → 原子替换
  PREROUTING+OUTPUT DNAT 目标为 127.0.0.1:8443 → 记状态/日志。fallback 模式连续成功≥threshold →
  先切回 DNAT 再停备用 xray。切换只影响新连接，存量 conntrack 会话自然过渡。
- switch：手动强制切换（演练/运维用）；status：模式/计数/WARP/服务/DNAT 目标；
  clean：停 timer+服务、删单元/配置/状态、恢复主路 DNAT；WARP 保留并提示。
- 日志：journal + `/var/log/vpn-relay-fallback.log`；任何输出不含密钥。

### 5. 客户端重配（部署步骤，非脚本改动）

- 本机与远端 198.51.100.40：用各自现有 UUID/pbk/sid（哈希已验证同源）拼新 VLESS 链接
  （地址 198.51.100.10:443，sni=www.icloud.com），`client/linux_setup.sh install --vless=...`
  重装（脚本自带备份）。链接作为交付物打印给用户（PC/手机换地址即用）。
- 远端同步更新 devtools 仓库到含本次改动的提交（脚本部署需要）。

### 6. 文档与记录

- `network/vpn/README.md`：架构图出口 IP/地域更新；多 SNI、白名单、兜底部署与管理章节；
  `## Issues` 新增 `2026-11-18 — 运营商/GFW 方向性封禁境外出口 IP`（症状/根因/解法/实测数据）。
- `relay/README.md`：兜底子系统说明。
- 完成后更新持久记忆（新出口 IP、中继已重建、旧 IP 被墙事实）。

### 部署顺序与回滚

1. 出口：重跑新 `exit/setup.sh --sni=<4列表> --allow-ip=198.51.100.10`（缓存一致已验证）
   → 回滚：`--allow-ip-off` + 恢复 config.json.bak（脚本写前备份）。
2. 中继：`relay/setup.sh --exit-ip=198.51.100.21`（清扫旧规则）→ 回滚 `--clean`。
3. 中继：`fallback.sh install ...` → 回滚 `fallback.sh clean`。
4. 双客户端重配 → 回滚：linux_setup.sh 自动备份的旧配置。
5. 兜底演练：出口临时 DROP 中继→443（远端脚本 trap EXIT 保证删除）→ 验证自动切 WARP →
   删规则 → 验证自动切回。任何一步失败即停，按上述回滚。

## 测试要点

- **层级**：L1 UT（bash sh_test，fake 命令）为主 + 现网功能验证（部署即验证，含兜底演练）。
  不新增 L2/L3（compose pair 不覆盖中继/白名单，保持 --skip-warp 行为不变）。
- **方法**：
  - `exit/setup_test.sh` 扩展：source-only 下测 SNI 列表解析/校验/去重、serverNames JSON
    构建、白名单规则规划（断言 allow 在 drop 前、不含 22 端口）、缓存 REALITY_SNIS 读写
    往返（临时目录覆盖 CONFIG_CACHE）。
  - `relay/setup_test.sh` 新增：sysctl 文本含 conntrack/route_localnet/bbr；规则规划函数
    对伪造的 `iptables -S` 输出（含旧 DNAT/Docker 链）断言清扫集合正确、hairpin 仅公网 IP 生成。
  - `relay/fallback_test.sh` 新增：状态机（注入假探测结果：失败×3→切 fallback、成功×3→切回、
    中途成功清零计数）；用 fixture reality.json（假密钥）生成配置断言 JSON 结构；
    断言生成/日志输出不含假私钥字符串。
  - fake 命令：PATH shim 目录伪造 iptables/systemctl/warp-cli/ssh，记录调用供断言；临时目录隔离。
- **环境**：L1 在本机（Alinux3，非 root）跑 `bazel test //network/vpn/...`；无 Docker、无真实
  安装、无网络副作用。现网验证需 root（sudo 密码走 stdin，不回显）与 SSH 到出口/远端。
- **特别注意**：bash 3.2 兼容（macOS 可跑 --help/source-only）；幂等（重跑不重复规则）；
  回滚（每步有 clean/备份）；安全（密钥不回显、白名单不碰 SSH、演练规则 trap 保证删除、
  不提交 tmp.secret/凭据）；出口机 Python 3.6（远端探测脚本不用 3.12 语法）。
- **完成证据**（dev-verify 逐项）：
  1. `bash -n` 全部改动脚本 + `git diff --check`
  2. `bazel test //network/vpn/...` 全绿（含新增用例；不可用时如实报告）
  3. 出口 `xray run -test` 通过；4 个 SNI 逐一握手+代理出海验证
  4. 白名单：远端直连出口 443 被丢包、中继可达
  5. 端到端：远端经中继 → ipify 显示 198.51.100.21；claude.ai 可达
  6. 演练：模拟封禁 ≤2 分钟自动切 WARP（ipify 变 CF IP）→ 解除 → 自动切回
  7. 幂等：relay/exit setup 重跑规则数不变；持久化服务 enabled
  8. README Issues 条目 + 架构更新落盘

## 非目标

- 不做 GA 持牌通道、tc 限速、定期自动换 EIP（上轮讨论的可选增强，本轮 YAGNI）。
- 不改 manage.sh 的链接轮换逻辑（链接仍用首位 SNI，备选列表文档化）。
- 不动 TUN / PAC / macOS 客户端脚本；PC/手机只换链接地址。
- 不做真实重启验证（仅确认持久化机制 enabled）。
- 不清理旧 jp 节点 198.51.100.23 本身（只清扫中继上指向它的转发规则）。