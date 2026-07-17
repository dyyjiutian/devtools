# Setproxy Safe Defaults Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Git SSH and Docker daemon proxying opt-in while managing the Linux dnf proxy safely on `setproxy on/off`.

**Architecture:** `tools/vpn/client/bin/setproxy` remains the single command and state owner. A new dnf state file records the previous `[main] proxy` setting and the exact value written by setproxy; an embedded Python helper applies and conditionally restores that setting through `sudo`. The existing shell regression suite supplies fake executables and a temporary dnf configuration path.

**Tech Stack:** Bash, embedded Python 3, dnf INI configuration, shell regression tests.

## Global Constraints

- `setproxy on` must not export `GIT_SSH_COMMAND` or edit Docker by default.
- `--git-ssh` enables Git SSH; `--docker-daemon` enables Docker daemon edits for that `on` invocation only.
- Linux systems with `dnf` receive `proxy=http://<HTTP_HOST>:<HTTP_PORT>` through `sudo`; macOS and systems without dnf are unchanged.
- `setproxy off` restores only state previously managed by setproxy and must preserve a proxy changed by another actor.
- Tests must not read or modify the host `/etc/dnf/dnf.conf`.

---

### Task 1: Define regressions for opt-in integrations

**Files:**
- Modify: `tools/vpn/client/setproxy_test.sh:22-170, 210-280`
- Test: `tools/vpn/client/setproxy_test.sh`

**Interfaces:**
- Consumes: `setproxy on --emit`, `--git-ssh`, `--docker-daemon`, and `VPN_DNF_CONF`.
- Produces: failing assertions for default Git SSH/Docker behaviour and dnf lifecycle behaviour.

- [x] **Step 1: Write the failing test assertions**

Add a fake `dnf` executable to `FAKE_BIN`, then change the initial `on --emit` assertions to require `unset GIT_SSH_COMMAND`. Add a second invocation that passes `--git-ssh` and requires an exported command. Change Docker's enabling invocation to:

```bash
"${SETPROXY}" on --http-port 8001 --docker-daemon >"${TMP_ROOT}/docker-on.stdout" 2>&1
```

Before that invocation, add a bare `on --http-port 8001` assertion that `${DOCKER_DAEMON_JSON}` is unchanged. Add a Linux dnf fixture and lifecycle:

```bash
DNF_CONF="${TMP_ROOT}/dnf.conf"
printf '[main]\nproxy=http://old-proxy:8080\n' >"${DNF_CONF}"
env -i HOME="${HOME_DNF}" PATH="${FAKE_BIN}:/usr/bin:/bin" FAKE_UNAME=Linux \
  VPN_DNF_CONF="${DNF_CONF}" "${SETPROXY}" on --http-port 9001 >/dev/null
assert_file_contains "${DNF_CONF}" 'proxy=http://127.0.0.1:9001'
env -i HOME="${HOME_DNF}" PATH="${FAKE_BIN}:/usr/bin:/bin" FAKE_UNAME=Linux \
  VPN_DNF_CONF="${DNF_CONF}" "${SETPROXY}" off >/dev/null
assert_file_contains "${DNF_CONF}" 'proxy=http://old-proxy:8080'
```

Then repeat `on`, replace the written proxy with `http://external:8080`, run `off`, and assert it remains.

- [x] **Step 2: Run the regression suite and verify it fails**

Run: `bash tools/vpn/client/setproxy_test.sh`

Expected: failure because the current default emits `GIT_SSH_COMMAND`, enables Docker without a flag, and has no dnf implementation.

- [x] **Step 3: Keep the test harness isolated**

Ensure the fake `sudo` continues to `exec "$@"`, and set `VPN_DNF_CONF` for every dnf test invocation. No test may use the default `/etc/dnf/dnf.conf` path.

- [x] **Step 4: Re-run the suite to confirm the intended red state**

Run: `bash tools/vpn/client/setproxy_test.sh`

Expected: the same targeted failure remains, with no host dnf configuration change.

### Task 2: Implement opt-in Git SSH and Docker daemon behaviour

**Files:**
- Modify: `tools/vpn/client/bin/setproxy:7-120, 260-305, 545-685`
- Test: `tools/vpn/client/setproxy_test.sh`

**Interfaces:**
- Consumes: `CLI_GIT_SSH_PROXY`, new `CLI_DOCKER_DAEMON`, and existing Docker state functions.
- Produces: `GIT_SSH_PROXY=false` by default and `DOCKER_DAEMON=false` by default.

- [x] **Step 1: Add the Docker option parsing test dependency**

The command parser must recognize `--docker-daemon` and set a boolean that is true only for this invocation. The usage text must contain:

```text
--docker-daemon       配置 Docker 守护进程代理（仅本次 on）
```

- [x] **Step 2: Implement the minimal option/default changes**

Set the final default in the existing Git SSH precedence chain to `false`:

```bash
GIT_SSH_PROXY="$(normalize_bool "$(first_nonempty "$CLI_GIT_SSH_PROXY" "${VPN_GIT_SSH_PROXY:-}" "$CONFIG_GIT_SSH_PROXY" "false")")"
```

Initialize `DOCKER_DAEMON=false`, set it on `--docker-daemon`, and replace the unconditional enable call in `do_on` with:

```bash
if $DOCKER_DAEMON; then
    configure_docker_proxy_on
fi
```

Keep `configure_docker_proxy_off` in `do_off` so an existing state file is restored even when `off` has no option.

- [x] **Step 3: Run the regression suite and verify it passes this portion**

Run: `bash tools/vpn/client/setproxy_test.sh`

Expected: Git SSH and Docker assertions pass; dnf assertions remain the only failing behaviour until Task 3.

### Task 3: Add guarded dnf proxy lifecycle management

**Files:**
- Modify: `tools/vpn/client/bin/setproxy:140-150, 545-710`
- Test: `tools/vpn/client/setproxy_test.sh`

**Interfaces:**
- Consumes: `VPN_DNF_CONF` (default `/etc/dnf/dnf.conf`), `HTTP_HOST`, `HTTP_PORT`, `sudo`, and `dnf` availability.
- Produces: `${PROXY_DIR}/setproxy-dnf-state.json` and a dnf `[main] proxy` lifecycle.

- [x] **Step 1: Implement dnf detection and state paths**

Add:

```bash
DNF_CONF="${VPN_DNF_CONF:-/etc/dnf/dnf.conf}"
DNF_STATE_FILE="${PROXY_DIR}/setproxy-dnf-state.json"
```

Skip all dnf operations when `$IS_DARWIN` is true or `command -v dnf` fails.

- [x] **Step 2: Implement `configure_dnf_proxy_on`**

Use `sudo python3` with arguments for the configuration path, state path, and `http://${HTTP_HOST}:${HTTP_PORT}`. The helper must parse only the `[main]` section, save the active original `proxy=` entries and the generated value as JSON, replace active `[main] proxy=` entries with exactly one generated entry, and preserve non-proxy lines. It must create a `[main]` section when absent.

- [x] **Step 3: Implement `configure_dnf_proxy_off`**

Use `sudo python3` with the same paths. If there is no state file, exit without changes. If active `[main] proxy=` entries are not exactly the state file's generated value, print a warning and leave both configuration and state intact. Otherwise remove the generated entry, restore the saved active original entries, and delete the state file.

- [x] **Step 4: Wire dnf lifecycle into `do_on` and `do_off`**

Call `configure_dnf_proxy_on` after writing shell configuration and before returning from `do_on`. Call `configure_dnf_proxy_off` from `do_off` before the success message. Propagate failures from `sudo` instead of reporting an enabled proxy when dnf configuration failed.

- [x] **Step 5: Run complete verification**

Run: `bash -n tools/vpn/client/bin/setproxy tools/vpn/client/install-setproxy.sh tools/vpn/client/setproxy_test.sh && bash tools/vpn/client/setproxy_test.sh`

Expected: shell syntax succeeds and the test script ends with `PASS: setproxy regression checks`.

### Task 4: Update user-facing documentation

**Files:**
- Modify: `tools/vpn/README.md:268-287, 438-440`
- Test: `tools/vpn/client/setproxy_test.sh`

**Interfaces:**
- Consumes: the final CLI semantics from Tasks 2 and 3.
- Produces: documented opt-in commands and system-level dnf side effect.

- [x] **Step 1: Document safe default examples**

Add examples for the three distinct actions:

```bash
setproxy on
setproxy on --git-ssh
setproxy on --docker-daemon
```

State that Linux hosts with dnf require sudo authentication because `setproxy on/off` manages `/etc/dnf/dnf.conf`.

- [x] **Step 2: Run final verification**

Run: `git diff --check && bash -n tools/vpn/client/bin/setproxy tools/vpn/client/install-setproxy.sh tools/vpn/client/setproxy_test.sh && bash tools/vpn/client/setproxy_test.sh`

Expected: exit code 0 and the regression suite reports `PASS: setproxy regression checks`.
