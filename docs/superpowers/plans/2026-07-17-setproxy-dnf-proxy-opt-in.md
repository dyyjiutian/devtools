# Setproxy dnf Proxy Opt-In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Require `--dnf-proxy` before `setproxy on` modifies dnf while preserving automatic safe restoration during `setproxy off`.

**Architecture:** Add an invocation-scoped Bash boolean beside `DOCKER_DAEMON` and gate only `configure_dnf_proxy_on`. Keep `configure_dnf_proxy_off` unconditional so previously managed state is restored. Extend the existing isolated shell regression harness and user documentation.

**Tech Stack:** Bash, embedded Python 3, shell regression tests, Markdown.

## Global Constraints

- `setproxy on` must not modify dnf by default.
- `setproxy on --dnf-proxy` must apply the selected HTTP proxy to dnf.
- `setproxy off` must restore managed dnf state without requiring `--dnf-proxy`.
- macOS and Linux systems without dnf must warn when `--dnf-proxy` is requested but still enable terminal proxy variables.
- Tests must use `VPN_DNF_CONF` and must never access `/etc/dnf/dnf.conf`.

---

### Task 1: Add failing opt-in regression coverage

**Files:**
- Modify: `network/vpn/client/setproxy_test.sh:217-330`
- Test: `network/vpn/client/setproxy_test.sh`

**Interfaces:**
- Consumes: `setproxy on`, `setproxy on --dnf-proxy`, `setproxy off`, `VPN_DNF_CONF`.
- Produces: regression assertions proving default no-op, explicit apply, automatic restore, and unavailable-platform warnings.

- [x] **Step 1: Add a default no-op assertion**

Create a temporary dnf configuration containing `proxy=http://old-proxy:8080`, run Linux `setproxy on --http-port 9001` without the new flag, and assert the old value remains:

```bash
env -i HOME="${HOME_DNF}" PATH="${FAKE_DNF_BIN}:${FAKE_BIN}:/usr/bin:/bin" \
    FAKE_UNAME=Linux VPN_DNF_CONF="${DNF_CONF}" \
    "${SETPROXY}" on --http-port 9001 >/dev/null
assert_file_contains "${DNF_CONF}" 'proxy=http://old-proxy:8080'
```

- [x] **Step 2: Require the flag for existing apply assertions**

Change both dnf apply invocations to:

```bash
"${SETPROXY}" on --http-port 9001 --dnf-proxy
```

Add a Darwin invocation with `--dnf-proxy` and assert stderr contains `当前系统不支持 dnf 代理配置`.

- [x] **Step 3: Run the suite and verify the intended failure**

Run: `bash network/vpn/client/setproxy_test.sh`

Expected: FAIL because the current implementation still changes dnf without a flag and rejects `--dnf-proxy` as unknown.

### Task 2: Implement the invocation-scoped dnf option

**Files:**
- Modify: `network/vpn/client/bin/setproxy:25-130, 860-875`
- Test: `network/vpn/client/setproxy_test.sh`

**Interfaces:**
- Consumes: new boolean `DNF_PROXY=false` and existing `dnf_available`/`configure_dnf_proxy_on`.
- Produces: parsed `--dnf-proxy` CLI behaviour and warning-only unsupported-platform handling.

- [x] **Step 1: Parse and document the flag in command help**

Add:

```bash
DNF_PROXY=false
```

and the parser branch:

```bash
--dnf-proxy)
    DNF_PROXY=true
    shift
    ;;
```

The help text must say `--dnf-proxy           为本次 on 配置 dnf 下载代理`.

- [x] **Step 2: Gate dnf apply and warn when unsupported**

Replace the unconditional call in `do_on` with:

```bash
if $DNF_PROXY; then
    if dnf_available; then
        configure_dnf_proxy_on
    else
        warn "当前系统不支持 dnf 代理配置；终端代理仍会启用"
    fi
fi
```

Keep `configure_dnf_proxy_off` unchanged in `do_off`.

- [x] **Step 3: Run syntax and regression checks**

Run: `bash -n network/vpn/client/bin/setproxy network/vpn/client/setproxy_test.sh && bash network/vpn/client/setproxy_test.sh`

Expected: exit code 0 and `PASS: setproxy regression checks`.

### Task 3: Update documentation and publish the PR revision

**Files:**
- Modify: `network/vpn/README.md:277-300, 444-450`
- Create: `docs/superpowers/plans/2026-07-17-setproxy-dnf-proxy-opt-in.md`

**Interfaces:**
- Consumes: final `--dnf-proxy` behaviour.
- Produces: documented commands and a pushed revision of PR #103.

- [x] **Step 1: Update examples and dnf lifecycle wording**

Document:

```bash
setproxy on --dnf-proxy       # 额外写入 dnf 的 HTTP 代理
```

State that bare `setproxy on` does not change dnf and bare `setproxy off` restores prior managed dnf state.

- [x] **Step 2: Run final verification**

Run: `git diff --check && bash -n network/vpn/client/bin/setproxy network/vpn/client/install-setproxy.sh network/vpn/client/setproxy_test.sh && bash network/vpn/client/setproxy_test.sh`

Expected: exit code 0 and `PASS: setproxy regression checks`.

- [x] **Step 3: Commit and update the existing PR**

Stage only the setproxy implementation, regression test, README, design, and plan. Commit with `feat: make dnf proxy opt-in`, then push `vpn_client_test` and verify PR #103 points to the new commit.
