# setproxy macOS and Git SSH Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the standalone setproxy command work cleanly with V2RayXS on macOS, preserve Linux support, and proxy Git SSH through SOCKS without editing SSH configuration.

**Architecture:** Add deterministic option/config/autodetection resolution to the standalone Bash command, write HTTP/SOCKS/Git SSH exports to the shared proxy environment file, and keep shell mutation explicit through `--emit`. Add a dependency-light regression harness with fake platform and networking commands, plus installer lifecycle tests in a temporary HOME.

**Tech Stack:** Bash 3.2+, curl, awk, nc, lsof/ss.

## Global Constraints

- Do not modify `~/.ssh/config`.
- macOS V2RayXS defaults are HTTP `8001` and SOCKS5 `1081`.
- Linux/command-line Xray defaults are HTTP `10809` and SOCKS5 `10808`.
- `--emit` standard output must contain shell code only.
- Domestic direct tests must bypass all proxy environment variables.
- Keep `proxy.env` compatible with Zsh and Bash.

---

### Task 1: Add failing setproxy and installer regression tests

**Files:**
- Create: `tools/vpn/client/setproxy_test.sh`

**Interfaces:**
- Consumes: `bin/setproxy` and `install-setproxy.sh`.
- Produces: assertions for macOS port detection, clean emit output, Git SSH export, direct curl bypass, and complete uninstall.

- [ ] Write a Bash test harness using a temporary HOME and fake `uname`, `lsof`, `curl`, and `nc`.
- [ ] Verify the current implementation fails because it lacks Git SSH export, pure `off --emit`, direct proxy bypass, config persistence, and complete uninstall.

### Task 2: Implement proxy resolution and Git SSH export

**Files:**
- Modify: `tools/vpn/client/bin/setproxy`

**Interfaces:**
- Consumes: host/port CLI options, VPN environment overrides, persisted config, listening ports.
- Produces: `proxy.env`, `setproxy.conf`, clean on/off emit output, optional `GIT_SSH_COMMAND`.

- [ ] Add argument parsing and validation.
- [ ] Add persisted config and macOS/Linux port autodetection.
- [ ] Add `GIT_SSH_COMMAND` and `--no-git-ssh`.
- [ ] Make emit output shell-code-only.
- [ ] Force direct test requests to bypass proxies.
- [ ] Improve macOS status hints.
- [ ] Run the focused regression harness.

### Task 3: Complete installer lifecycle

**Files:**
- Modify: `tools/vpn/client/install-setproxy.sh`

**Interfaces:**
- Consumes: HOME and detected shell rc.
- Produces: managed PATH installation and complete managed cleanup.

- [ ] Replace the one-line PATH marker with a managed block while recognizing the legacy marker.
- [ ] Warn about existing shell function conflicts.
- [ ] Remove binary, managed rc blocks, proxy environment, and saved config on uninstall.
- [ ] Run the focused regression harness.

### Task 4: Install locally and retire inline functions

**Files:**
- Modify: `/Users/devuser/.zshrc`
- Create: `/Users/devuser/.zshrc.bak.<timestamp>`
- Install: `/Users/devuser/.local/bin/setproxy`

**Interfaces:**
- Consumes: tested repository scripts.
- Produces: PATH-resolved standalone command and commented legacy inline functions.

- [ ] Back up `.zshrc` and record the SSH config digest.
- [ ] Comment the old inline proxy function/state block.
- [ ] Install the command and enable it with V2RayXS ports.
- [ ] Verify new-shell exports, on/off emit, Git SSH ProxyCommand expansion, syntax, and unchanged SSH config.
