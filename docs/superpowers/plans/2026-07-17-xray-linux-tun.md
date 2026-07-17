# Xray Linux TUN Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in Linux host TUN mode to `linux_setup.sh` without changing the default SOCKS/HTTP installation.

**Architecture:** Keep Xray v26.3.27 and add an `xray0` inbound only for `--tun`. A dedicated helper manages an IPv4/IPv6 policy table for locally originated traffic, while a dynamic Xray service UID and outbound socket marks use the main table to prevent loops, including internal DNS; systemd binds routing setup and teardown to the Xray client lifecycle.

**Tech Stack:** Bash, Xray JSON configuration, systemd, Linux iproute2 policy routing, shell regression tests, Markdown.

## Global Constraints

- Bare `install` must preserve the existing SOCKS5/HTTP-only behaviour.
- `install --tun` must retain SOCKS5 and HTTP inbounds in addition to `xray0`.
- Existing private/China-direct and foreign-proxy Xray rules remain unchanged.
- Only locally originated host traffic is captured; forwarded container and virtual-machine traffic is excluded.
- Managed routes must be idempotent and removable during reinstall, service stop, and `clean`.
- Xray v26.3.27 remains pinned; TUN mode supports TCP/UDP and documents the lack of ICMP.
- Tests must use temporary paths and a fake `ip`; they must not modify the host network or `/etc`.

---

### Task 1: Add failing configuration and CLI regression coverage

**Files:**
- Create: `tools/vpn/client/linux_setup_test.sh`
- Modify: `tools/vpn/client/linux_setup.sh`

**Interfaces:**
- Consumes: `linux_setup.sh --help`, sourceable `write_client_config`, `TUN_MODE`.
- Produces: assertions for default compatibility and the requested TUN JSON.

- [x] **Step 1: Write the failing CLI and render tests**

Create a temporary configuration directory, source `linux_setup.sh` without executing its main dispatch, and assert:

```bash
bash "$LINUX_SETUP" --help | grep -q -- '--tun'
TUN_MODE=false write_client_config
assert_file_not_contains "$cfg" '"protocol": "tun"'
TUN_MODE=true write_client_config
assert_file_contains "$cfg" '"name": "xray0"'
assert_file_contains "$cfg" '"mark": 255'
```

- [x] **Step 2: Run the new test and verify RED**

Run: `bash tools/vpn/client/linux_setup_test.sh`

Expected: FAIL because help has no `--tun`, sourcing executes the installer, and no TUN JSON is rendered.

- [x] **Step 3: Add source-safe dispatch and minimal TUN rendering**

Add `TUN_MODE=false`, parse `--tun`, guard the bottom-level dispatch with:

```bash
if [[ "${LINUX_SETUP_SOURCE_ONLY:-false}" != "true" ]]; then
    main "$@"
fi
```

Render a `tun` inbound with `name: xray0`, `MTU: 1500`, and HTTP/TLS/QUIC sniffing. In TUN mode add `sockopt.mark: 255` to both `proxy` and `direct` outbounds.

- [x] **Step 4: Run the new test and verify GREEN**

Run: `bash tools/vpn/client/linux_setup_test.sh`

Expected: configuration assertions pass.

### Task 2: Add the tested Linux policy-route helper

**Files:**
- Create: `tools/vpn/client/bin/xray-tun-route`
- Modify: `tools/vpn/client/linux_setup_test.sh`

**Interfaces:**
- Consumes: `XRAY_TUN_IFACE`, `XRAY_TUN_TABLE`, `XRAY_TUN_MARK`, `XRAY_TUN_BYPASS_UID`, `ip`, and `sysctl`.
- Produces: `up`, `down`, and `status` actions for the managed routes and rules.

- [x] **Step 1: Write failing helper tests with a fake `ip`**

Log fake `ip` arguments and assert `up` requests:

```text
-4 route replace default dev xray0 table 1001
-4 rule add priority 9990 uidrange 4242-4242 lookup main
-4 rule add priority 10000 fwmark 255 lookup main
-4 rule add priority 10010 uidrange 0-4294967294 lookup 1001
```

Assert equivalent IPv6 operations and exact deletion operations for `down`. Run repeated `up` and `down` calls to require idempotent behaviour.

- [x] **Step 2: Run helper tests and verify RED**

Run: `bash tools/vpn/client/linux_setup_test.sh`

Expected: FAIL because `bin/xray-tun-route` does not exist.

- [x] **Step 3: Implement the minimal route helper**

Implement strict action parsing, exact-rule cleanup before addition, IPv4 as required, IPv6 as best-effort, and a read-only `status` action. Match only locally originated packets with `uidrange`; bypass the complete dynamic Xray UID before matching marked sockets and general local traffic.

- [x] **Step 4: Run helper tests and verify GREEN**

Run: `bash tools/vpn/client/linux_setup_test.sh`

Expected: helper assertions pass without invoking the real `ip` command.

### Task 3: Bind TUN routing to installation and systemd lifecycle

**Files:**
- Modify: `tools/vpn/client/linux_setup.sh`
- Modify: `tools/vpn/client/linux_setup_test.sh`

**Interfaces:**
- Consumes: repository helper `bin/xray-tun-route` and variables `XRAY_SYSTEMD_DIR`, `XRAY_TUN_HELPER_PATH`.
- Produces: `xray-client-tun-routing.service`, conditional `Wants`, safe mode switching, status, and cleanup.

- [x] **Step 1: Write failing generated-unit and cleanup tests**

Assert that TUN mode generates a oneshot unit containing:

```ini
After=xray-client.service
Requires=xray-client.service
BindsTo=xray-client.service
ExecStart=/usr/local/libexec/xray-client-tun-route up
ExecStop=/usr/local/libexec/xray-client-tun-route down
RemainAfterExit=yes
```

Assert the TUN Xray unit wants the route unit, while normal mode does not. With fake `systemctl` and temporary paths, assert reinstall/cleanup invokes helper `down` and removes only managed files.

- [x] **Step 2: Run the suite and verify RED**

Run: `bash tools/vpn/client/linux_setup_test.sh`

Expected: FAIL because TUN unit generation and cleanup functions are absent.

- [x] **Step 3: Implement installation, transition, and status integration**

Use overridable defaults:

```bash
XRAY_SYSTEMD_DIR="${XRAY_SYSTEMD_DIR:-/etc/systemd/system}"
XRAY_TUN_HELPER_PATH="${XRAY_TUN_HELPER_PATH:-/usr/local/libexec/xray-client-tun-route}"
```

Install the helper with mode `0755`, generate the routing unit only in TUN mode, remove stale routing before every install, and show `ip link`, helper status, and unit status in `do_status`. Make `do_clean` stop routing before Xray and remove both managed units.

- [x] **Step 4: Run the suite and verify GREEN**

Run: `bash tools/vpn/client/linux_setup_test.sh`

Expected: all Linux setup regression checks pass.

### Task 4: Document and verify the complete change

**Files:**
- Modify: `tools/vpn/README.md`
- Modify: `tools/vpn/client/linux_setup.sh`
- Modify: `tools/vpn/client/linux_setup_test.sh`
- Modify: `docs/superpowers/plans/2026-07-17-xray-linux-tun.md`

**Interfaces:**
- Consumes: final CLI and service behaviour.
- Produces: user-facing installation, rollback, limitation, and verification instructions.

- [x] **Step 1: Document TUN usage and rollback**

Add an example:

```bash
sudo ./linux_setup.sh install --tun --vless="vless://..."
```

Explain automatic host TCP/UDP capture, retained China-direct routing, excluded forwarded traffic, redundant-but-compatible `setproxy`, lack of ICMP in v26.3.27, and switching back by reinstalling without `--tun`.

- [x] **Step 2: Run final verification**

Run:

```bash
git diff --check
bash -n tools/vpn/client/linux_setup.sh tools/vpn/client/bin/xray-tun-route tools/vpn/client/linux_setup_test.sh
bash tools/vpn/client/linux_setup_test.sh
bash tools/vpn/client/setproxy_test.sh
```

Expected: all commands exit zero, Linux setup reports its PASS line, and setproxy reports `PASS: setproxy regression checks`.

- [ ] **Step 3: Review the diff and commit only scoped files**

Confirm `git status --short` still shows the two unrelated user-owned tests as untracked and unstaged. Stage only the design, plan, Linux setup implementation/test/helper, and VPN README, then commit the TUN feature.

### Task 5: Apply code-review hardening

**Files:**
- Modify: `tools/vpn/client/bin/xray-tun-route`
- Modify: `tools/vpn/client/linux_setup.sh`
- Modify: `tools/vpn/client/linux_setup_test.sh`
- Modify: `docs/superpowers/specs/2026-07-17-xray-linux-tun-design.md`

**Interfaces:**
- Consumes: reviewer findings against commit `af20dba`.
- Produces: safe reverse-path filtering, internal DNS bypass, startup readiness, source compatibility, and exact route ownership.

- [x] **Step 1: Reproduce each review issue with a failing test**

Cover `rp_filter` save/restore, delayed `xray0` creation, sourced `proxy on`, an occupied rule priority, exact route deletion, and a dedicated Xray UID bypass.

- [x] **Step 2: Implement the review fixes**

Use a systemd `DynamicUser` in TUN mode, persist its runtime UID for teardown, wait up to five seconds for `xray0`, safely manage `rp_filter`, reject conflicting route/rule ownership, and preserve normal sourced proxy dispatch.

- [x] **Step 3: Run the focused Linux TUN regression suite**

Run: `bash tools/vpn/client/linux_setup_test.sh`

Expected: all seven Linux setup TUN regression sections pass.
