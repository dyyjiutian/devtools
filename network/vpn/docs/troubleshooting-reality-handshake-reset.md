# 排查记录：VLESS + Reality 客户端 TLS 握手被 reset

> 时间：2026-06-28 ｜ 节点：新加坡出口 ECS（Alibaba Cloud Linux 3，出口 IP `198.51.100.23`）
> 结论先行：**根因是 Reality 伪装目标站 `dest=www.microsoft.com` 的 TLS 证书链变大（8273 字节），超过 Reality 中继偷证书握手的处理上限，导致所有 Reality 握手在服务端失败。与当晚装 codex / 跑 `shell/bash/setup.sh` / 做开发完全无关，只是时间上的巧合。**

---

## 1. 现象

客户端（macOS，链路 `客户端 → 中继 → 出口`）走 SOCKS5 访问外网，TLS 握手阶段被重置：

```
$ curl -x socks5h://127.0.0.1:1081 -v --connect-timeout 10 -o /dev/null https://www.google.com/
* SOCKS5 request granted.
* TLS handshake, Client hello (1):
* Recv failure: Connection reset by peer
* LibreSSL/3.3.6: error:02FFF036:system library:func(4095):Connection reset by peer
curl: (35) Recv failure: Connection reset by peer
```

特征：SOCKS5 协商成功 → 发出 Client Hello → 约 2s 后 `Connection reset by peer`。

已自查且确认正常：VLESS 各参数、client→relay、relay→exit 的端口与路由转发。

---

## 2. 架构回顾

```
国内客户端 ──VLESS+Reality──► 杭州中继(iptables DNAT 纯转发) ──► 新加坡出口(Xray VLESS+Reality) ──► 目标站点
                                                                  伪装 dest = www.microsoft.com
```

- 中继只做 TCP 透传，不解密。
- 出口 Xray 解出 VLESS，再用 `freedom` 出站访问目标。
- Reality 的关键机制：**出口服务端对每个握手都会去连 `dest`（伪装站），把真实的 ServerHello/证书中继给客户端**，以此把流量伪装成访问 `dest` 的正常 HTTPS。

---

## 3. 排查思路与过程

排查的主线：**沿数据链路逐段缩小范围，用“同机自测”消除变量，最后用 A/B 对照锁定根因。**

### 3.1 先确认出口节点本身是否健康

```bash
systemctl is-active xray            # active
ss -tlnp | grep -E ':443|:10085|:40000'
```

- xray 服务在跑，443 / 10085(stats) / 40000(warp) 均在监听。
- 意外发现：**有两个 xray 进程**，其中一个是开发时遗留的测试客户端 `xray run -config /tmp/reality_test.json`（监听 socks 10810，回连本机 443）。这恰好是一个现成的探针。

### 3.2 关键判断：用“同机自测”消除时钟 / 网络变量

用遗留的测试客户端直接打本机 Reality 服务端：

```bash
curl -x socks5h://127.0.0.1:10810 -v --connect-timeout 12 -o /dev/null https://www.google.com/
# → SSL_ERROR_SYSCALL in connection to www.google.com:443（与线上同样的失败）
```

**本机自测同样失败**，意义重大：

- 客户端与服务端在同一台机器、共享同一时钟 → **排除时钟漂移**（Reality 对时间敏感）。
- 不经过中继和公网 → **排除中继转发、公网链路、MTU 黑洞**。
- 失败点被收敛到「出口 xray 自身」。

### 3.3 校验密钥 / UUID / shortId / SNI —— 全部匹配

```bash
xray x25519 -i "REDACTED-REALITY-PRIVATE-KEY"
# PrivateKey 推导出的 PublicKey = REDACTED-REALITY-PUBLIC-KEY
```

- 服务端 `privateKey` 推导出的公钥，与 `/root/.vpn_exit_config` 的 `PUBLIC_KEY`、测试客户端用的 `publicKey` **完全一致**。
- `shortId`、`UUID(user1)`、`serverNames` 也都对得上。

→ **参数没错，排除配置漂移/密钥不匹配。**

### 3.4 确认出口的“出网能力”是好的

```bash
curl -4 https://www.google.com/      # HTTP 200（IPv4 直连 OK）
curl -6 https://www.google.com/      # 连不上（本机无 IPv6 出口，仅有 AAAA 解析，但 freedom 配了 UseIPv4，无影响）
curl https://www.microsoft.com/      # HTTP 200（dest 直连也 OK！）
```

→ 出口到目标站、到 dest 的网络本身都正常。问题不在“能不能出网”。

### 3.5 抓服务端内部原因：开 `show:true` 调试

为不动生产，**另起一个调试用 Reality 服务端（:8443，相同密钥/SNI/dest，`loglevel:debug` + `realitySettings.show:true`）**，再用调试客户端打它：

客户端侧报错：

```
proxy/vless/outbound: failed to find an available destination > common/retry: [EOF]
```

即服务端在握手期间**直接关闭连接（EOF）**，客户端表现为 Client Hello 后被 reset。

服务端 `show` 调试输出（关键）：

```
hs.c.ClientShortId: 7fb539b1aaadee17     ← 客户端认证通过
hs.c.conn == conn: true                  ← 已识别为合法 Reality 客户端
len(s2cSaved): 1448  Server Hello: 127
len(s2cSaved): ....   Change Cipher Spec / Encrypted Extensions
len(s2cSaved): ....   Certificate: 8273
hs.c.isHandshakeComplete.Load(): false   ← 与 dest 的伪装 TLS 握手始终没完成
```

解读：

- 客户端认证**已通过**（不是密钥/SNI 问题）。
- 服务端去连 `dest`，读到了 ServerHello、CCS、EncryptedExtensions，以及一个 **8273 字节的 Certificate**，但 `isHandshakeComplete` 始终为 `false` —— **伪装握手没跑完**，于是把连接判为 invalid 并关闭。
- 多次连接里 `len(s2cSaved)` 在 1448 / 2896 / 5544 等之间，始终凑不齐完整握手（光证书就要 8273 字节）。

> 疑点：为什么 `curl` 直连 `www.microsoft.com` 能拿到完整证书（200），Reality 却凑不齐？因为 Reality 偷证书握手对 dest 返回的握手大小有处理上限，证书链过大就会失败。这与普通 curl 的读取方式不同。

### 3.6 A/B 对照：锁定是 dest 证书过大

用相同手法换不同 dest，端到端各跑一次 `curl https://www.google.com`：

| dest | 证书大小 | `isHandshakeComplete` | 隧道结果 |
|------|---------|----------------------|---------|
| www.microsoft.com | **8273** | false | **HTTP 000（坏）** |
| www.icloud.com | 4772 | true | HTTP 200 |
| addons.mozilla.org | 4130 | true | HTTP 200 |
| www.apple.com | 4737 | true | HTTP 200 |

→ **结论确凿**：`www.microsoft.com`（Akamai 托管）证书链增大后超出 Reality 处理范围，所有握手失败；换成 ~4–5KB 证书的小站点立即恢复。

---

## 4. 根因

`www.microsoft.com` 的 TLS 证书链膨胀到 8273 字节，超过 Xray Reality 中继偷证书握手能处理的大小，导致出口服务端**对每一个 Reality 握手都失败**（`handshake did not complete successfully`），并以 EOF 关闭连接 → 客户端在 Client Hello 后被 `Connection reset by peer`。

这是 dest 外部站点证书变化触发的，**与本机当晚的 codex / `bash/setup.sh` / 开发活动无因果关系**。

---

## 5. 修复

把出口的伪装域名换成证书较小、支持 TLS1.3 的站点 `www.icloud.com`：

```bash
# 1. 备份
sudo cp /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.bak.$(date +%F_%H%M%S)
sudo cp /root/.vpn_exit_config        /root/.vpn_exit_config.bak.$(date +%F_%H%M%S)

# 2. 改 dest + serverNames（config.json）与 REALITY_SNI（参数缓存）
sudo sed -i 's/www\.microsoft\.com/www.icloud.com/g' /usr/local/etc/xray/config.json
sudo sed -i 's/www\.microsoft\.com/www.icloud.com/g' /root/.vpn_exit_config

# 3. 重启
sudo systemctl restart xray
```

仓库默认值也一并改掉，避免重装回退（`network/vpn/exit/setup.sh`、`client/macos_setup.sh`、`client/linux_setup.sh`、`README.md`）。

### 客户端

只需把 VLESS 链接里的 `sni=www.microsoft.com` 改为 `sni=www.icloud.com`，重连即可。`pbk` / `sid` / `uuid` / 端口都不变。可用：

```bash
sudo ./network/vpn/exit/manage.sh vless <user> <relay_ip>
```

---

## 6. 验证

用真实凭据（user1）+ `sni=www.icloud.com` 打线上 443：

```
google via tunnel: HTTP 200
exit IP via tunnel: 198.51.100.23
```

服务端日志恢复正常的 `Xtls Unpadding / CopyRawConn splice`，不再出现 `handshake did not complete successfully`。

收尾：清理了开发遗留的测试进程 `xray run -config /tmp/reality_test.json` 与临时文件。

---

## 7. 经验总结

1. **同机自测是利器**：把 client 和 server 放同一台机自测，一步消除时钟、公网、中继、MTU 等一大批变量，快速把范围收敛到进程内部。
2. **现象会骗人**：`Connection reset` 容易让人怀疑公网/中继/GFW，但真正的失败点在出口服务端的伪装握手。
3. **时间相关性 ≠ 因果**：故障出现在“装 codex + 跑脚本 + 开发”之后，但根因是外部 dest 证书变化，纯属巧合。不要被操作时间线带偏。
4. **Reality 选 dest 的硬性要求**：必须支持 TLS1.3 + HTTP/2，且**证书链要小**。`www.microsoft.com` 这类经 CDN、证书链可能变大的站点不是好选择；优先 `www.icloud.com`、`addons.mozilla.org`、`www.apple.com` 等。
5. **善用 `realitySettings.show:true`**：能直接看到 `ClientShortId`、`conn==conn`、`isHandshakeComplete`、dest 证书大小等内部状态，是定位 Reality 握手问题最有效的手段。

---

## 8. 快速排查清单（下次复用）

```bash
# 1. 出口服务与端口
systemctl is-active xray; ss -tlnp | grep -E ':443|:10085|:40000'

# 2. 校验密钥一致
sudo grep -E 'PRIVATE_KEY|PUBLIC_KEY|SHORT_ID|REALITY_SNI' /root/.vpn_exit_config
xray x25519 -i "<privateKey>"   # 推导公钥应与 PUBLIC_KEY 一致

# 3. 出口出网 & dest 可达
curl -4 -sS -o /dev/null -w '%{http_code}\n' https://www.google.com/
curl   -sS -o /dev/null -w '%{http_code}\n' https://<dest>/

# 4. 起调试服务端看 Reality 内部（关注 isHandshakeComplete 与 Certificate 大小）
#    config: loglevel=debug, realitySettings.show=true
#    若 dest 证书过大 → 换 dest

# 5. 端到端自测（用真实凭据 + 正确 sni 打本机 443）
curl -x socks5h://127.0.0.1:<port> -sS -o /dev/null -w '%{http_code}\n' https://www.google.com/
```
