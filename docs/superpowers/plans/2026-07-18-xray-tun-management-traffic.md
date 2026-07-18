# Xray TUN Management Traffic Protection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Protect replies to arbitrary inbound ECS connections, including SSH and ping, while retaining host-local TUN routing for outbound traffic.

**Architecture:** Extend `bin/xray-tun-route` with a netfilter adapter that prefers an isolated nftables table and falls back to isolated IPv4/IPv6 iptables mangle chains. Install connection marks before policy routes, restore packet marks on output, and tear down only rules owned by this helper. Keep the existing policy-route and sysctl logic, but make firewall setup part of the same transactional `up`/`down` lifecycle.

**Tech Stack:** Bash, `iproute2`, nftables or iptables/ip6tables, systemd oneshot service, existing shell regression harness with fake commands.

## Global Constraints

- Never modify real system routes, firewall state, or services during tests.
- Keep `set -euo pipefail` and existing Bash compatibility.
- Do not flush or rewrite firewall tables/chains not owned by this helper.
- Preserve normal non-TUN configuration and proxy behavior.
- Do not print VLESS credentials or other sensitive configuration in diagnostics.

---

### Task 1: Add failing fake-firewall regression tests

**Files:**
- Modify: `tools/vpn/client/linux_setup_test.sh:70-215`
- Modify: `tools/vpn/client/linux_setup_test.sh:292-307`

**Interfaces:**
- Consumes: existing `run_tun_helper`, fake `ip`, fake `sysctl`, and temporary state files.
- Produces: assertions for nft preference, iptables fallback, ordering, cleanup, and rollback.

- [x] **Step 1: Add fake netfilter commands and logs**

Add `fake_nft`, `fake_iptables`, and `fake_ip6tables` beside the existing fake commands. Each appends its arguments to the configured log and exits successfully unless a failure environment variable is set. Make `fake_nft list ruleset` emit a marker when `FAKE_NFT_VERIFY=true`.

- [x] **Step 2: Add a test for nftables connection protection**

Run the helper with `NFT_BIN`, `IPTABLES_BIN`, and `IP6TABLES_BIN` pointing to fakes. Assert the nft log contains an isolated `inet` table, an input/prerouting rule that excludes `xray0` and marks new inbound connections `255`, and an output rule that restores the connection mark to packet mark `255`.

- [x] **Step 3: Add a test for ordering and cleanup**

Record all fake command calls in one ordered log. Assert firewall setup occurs before `-4 route replace default dev xray0 table 1001`, and `down` deletes the firewall object as well as the IPv4/IPv6 policy routes. Call `up` twice and assert the helper first removes its owned firewall object before reinstalling it.

- [x] **Step 4: Add fallback and fail-closed tests**

Make the fake nft command fail detection and assert iptables plus ip6tables are used. Make all three backends unavailable and assert `up` fails without any `route replace` call. Make firewall verification fail after setup and assert the helper removes the firewall object and restores both `rp_filter` values.

- [x] **Step 5: Run the focused test and verify it fails for the missing behavior**

Run:

```bash
bash tools/vpn/client/linux_setup_test.sh
```

Expected: FAIL at the first new firewall assertion because the current helper has no firewall adapter.

### Task 2: Implement the firewall adapter in the TUN helper

**Files:**
- Modify: `tools/vpn/client/bin/xray-tun-route:4-20`
- Modify: `tools/vpn/client/bin/xray-tun-route:120-240`

**Interfaces:**
- Consumes: `NFT_BIN`, `IPTABLES_BIN`, `IP6TABLES_BIN`, existing `XRAY_TUN_MARK`, and helper state directory.
- Produces: `detect_firewall_backend`, `firewall_up`, `firewall_down`, and `firewall_backend` state used by route lifecycle.

- [x] **Step 1: Add injectable command paths and firewall constants**

Define defaults for `NFT_BIN`, `IPTABLES_BIN`, and `IP6TABLES_BIN`, plus an owned nft table name, iptables chain names, and a backend state file under `/run/xray-client-tun`. Keep mark `255` aligned with the existing Xray sockopt and `ip rule`.

- [x] **Step 2: Implement backend detection**

Prefer nft only when the command exists and a minimal `nft -c`/list probe succeeds. Otherwise require both IPv4 and IPv6 iptables commands. Record the selected backend in the state file so `down` can remove the same backend without relying on current autodetection.

- [x] **Step 3: Implement nftables setup and teardown**

Create a dedicated `inet xray_client_tun` table and rules equivalent to:

```nft
chain prerouting {
    type filter hook prerouting priority mangle; policy accept;
    iifname "xray0" return
    iifname != "xray0" ct state new ct mark 0 ct mark set 255 meta mark set 255
}
chain output {
    type route hook output priority mangle; policy accept;
    ct mark 255 meta mark set 255
}
```

Use a dedicated table so cleanup can delete only this helper’s rules. Verify the table/rules are visible after creation. If setup or verification fails, delete the table and return failure.

- [x] **Step 4: Implement iptables fallback setup and teardown**

Create dedicated IPv4 and IPv6 mangle chains, attach them to `PREROUTING` and `OUTPUT`, exclude `xray0`, set connmark `255` for new inbound packets, and restore packet mark `255` on output. Delete only the jump rules and dedicated chains during cleanup. Treat either family failing as a complete setup failure.

- [x] **Step 5: Keep cleanup idempotent**

Make `firewall_down` tolerate missing state, already-deleted objects, and a stopped Xray service. Remove the backend state file only after cleanup attempts. Never use `iptables -F` on built-in chains or `nft flush ruleset`.

### Task 3: Integrate firewall protection transactionally with policy routing

**Files:**
- Modify: `tools/vpn/client/bin/xray-tun-route:212-239`
- Modify: `tools/vpn/client/linux_setup_test.sh:150-215`

**Interfaces:**
- Consumes: firewall adapter from Task 2 and existing `routes_up`, `routes_down`, `up_family`, `down_family`.
- Produces: fail-closed TUN startup and complete rollback.

- [x] **Step 1: Install firewall protection before adding TUN policy routes**

In `routes_up`, after `rp_filter` preparation and before `up_family -4`, call `firewall_up`. If it fails, restore `rp_filter` and return without any policy route changes.

- [x] **Step 2: Roll back firewall protection on route failure**

If IPv4 route setup fails, call `firewall_down` and restore `rp_filter`. If IPv6 route setup is optional as today, remove only the failed IPv6 policy route while retaining the successfully installed IPv4 protection; if IPv6 firewall setup itself cannot be installed, fail the whole startup before routes are added.

- [x] **Step 3: Remove firewall protection during shutdown**

In `routes_down`, delete IPv4/IPv6 policy routes first while the mark rule still protects replies, then call `firewall_down`, restore `rp_filter`, and remove UID state. Preserve idempotency for repeated `down` calls.

- [x] **Step 4: Run the focused regression test and verify green**

Run:

```bash
bash tools/vpn/client/linux_setup_test.sh
```

Expected: all existing and new fake-firewall assertions pass.

### Task 4: Update operator documentation and validation commands

**Files:**
- Modify: `tools/vpn/README.md:232-249`
- Modify: `tools/vpn/client/linux_setup.sh:60-100`

**Interfaces:**
- Consumes: implemented firewall backend behavior and existing status/clean commands.
- Produces: accurate TUN safety guidance and diagnostics.

- [x] **Step 1: Document dynamic inbound-connection protection**

Explain that any remote SSH client and any remote ping peer are protected dynamically; no source IP needs to be configured. Clarify that cloud security groups and ICMP firewall rules remain outside this script.

- [x] **Step 2: Document backend prerequisites and rollback**

Document nftables preference, iptables fallback, fail-closed behavior, and the console recovery commands for a server that lost network access.

- [x] **Step 3: Correct the ping verification note**

State that Xray TUN itself does not proxy ICMP, but host ping replies are preserved by the management-traffic mark rules; tunnel health should still be checked with HTTP/SSH or the existing status command.

- [x] **Step 4: Add concise helper diagnostics**

Extend helper `status` output to show the selected firewall backend and owned protection object when present, without exposing credentials.

### Task 5: Run full verification and review the branch

**Files:**
- No new files.

- [x] **Step 1: Run shell syntax checks**

```bash
bash -n tools/vpn/client/linux_setup.sh
bash -n tools/vpn/client/bin/xray-tun-route
bash -n tools/vpn/client/linux_setup_test.sh
```

Expected: all commands exit 0.

- [x] **Step 2: Run the complete Linux VPN regression test**

```bash
bash tools/vpn/client/linux_setup_test.sh
```

Expected: `PASS: linux_setup TUN regression checks`.

- [x] **Step 3: Inspect the final diff**

```bash
git diff --check
git diff --stat
git status --short
```

Confirm only the TUN helper, its tests, and the scoped documentation/plan/spec files changed.

- [x] **Step 4: Commit the implementation**

```bash
git add tools/vpn/client/bin/xray-tun-route \
  tools/vpn/client/linux_setup_test.sh \
  tools/vpn/README.md \
  tools/vpn/client/linux_setup.sh
git commit -m "fix: preserve inbound traffic in linux tun mode"
```
