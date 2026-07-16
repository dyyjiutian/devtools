# Docker Dev Image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reproducible Alibaba Cloud Linux 3 development image that supports Dev Container, docker run, SSH, and runtime admin UID/GID synchronization.

**Architecture:** Keep the existing terminal, Git, and agent configuration directories as source templates. Add a container layer with a Dockerfile, root entrypoint, runtime user synchronization, Docker Bake targets, Dev Container metadata, and a host-side run wrapper. The image pre-creates `admin:1000:1000`; root entrypoint reconciles it to the host identity before dropping privileges.

**Tech Stack:** Alibaba Cloud Linux 3, Dockerfile, Docker Buildx Bake, POSIX/Bash shell, Dev Container JSON, OpenSSH, existing Git configuration scripts.

## Global Constraints

- Never bake API keys, OAuth state, SSH private keys, or personal Git identity into the image.
- Keep `USER root` for the image entrypoint so runtime UID/GID reconciliation can run.
- Never chown `/workspace` by default because it may be a host bind mount.
- Preserve user-owned configuration outside devtools-managed marker blocks.
- Direct `docker run --user admin` is not the supported dynamic-sync path; use the wrapper or `--user root` with `DEV_UID`/`DEV_GID`.

---

### Task 1: Add failing container contract tests

**Files:**
- Create: `containers/alinux3/tests/entrypoint.bats`
- Create: `containers/alinux3/tests/run-docker-tests.sh`
- Create: `containers/alinux3/BUILD.bazel`

**Interfaces:**
- Tests consume `containers/alinux3/entrypoint.sh` and the built `devtools-alinux3:test` image.
- Tests produce a repeatable exit status for shell syntax, image metadata, runtime identity, and workspace ownership.

- [ ] **Step 1: Write tests for the desired runtime contract**

  Add tests that assert the entrypoint source passes `bash -n`, the image starts as root, a non-default `DEV_UID`/`DEV_GID` makes `whoami` return `admin`, and a file created in `/workspace` has the requested numeric owner.

- [ ] **Step 2: Run the tests and verify the expected failure**

  Run:

  ```bash
  bash containers/alinux3/tests/run-docker-tests.sh
  ```

  Expected: fail because the Dockerfile, entrypoint, and test image do not exist yet.

- [ ] **Step 3: Add the Bazel test target without hiding Docker failures**

  Register only host-safe syntax/help tests in `containers/alinux3/BUILD.bazel`; keep Docker integration tests invoked explicitly because they require a Docker daemon.

- [ ] **Step 4: Commit the test contract**

  ```bash
  git add containers/alinux3/tests containers/alinux3/BUILD.bazel
  git commit -m "test: define alinux3 container contract"
  ```

### Task 2: Build the Alibaba Cloud Linux 3 image

**Files:**
- Create: `containers/alinux3/Dockerfile`
- Create: `containers/alinux3/versions.env`
- Create: `docker-bake.hcl`

**Interfaces:**
- Consumes the existing `terminal/`, `vcs/git/`, and `agent/` configuration trees.
- Produces targets named `alinux3-minimal`, `alinux3-full`, and `alinux3-ssh`.

- [ ] **Step 1: Add the pinned build variables and image targets**

  Define `BASE_IMAGE`, Node.js and CLI version variables in `versions.env`, and configure Buildx Bake targets to pass `INSTALL_AI_CLI`, `ENABLE_SSH`, and the image tag to the Dockerfile.

- [ ] **Step 2: Add the minimal Dockerfile stage**

  Use the Alibaba Cloud Linux 3 official registry image, install shell, Git, editor, terminal, archive, and SSH client dependencies with the detected RPM package manager, create `admin:1000:1000`, install passwordless sudo for development, and copy the repository configuration templates under `/etc/devtools`.

- [ ] **Step 3: Add the full CLI stage**

  Install Node.js and the Claude Code and Codex npm packages using the pinned version variables, install Cursor Agent using its official installer, and verify all three commands exist during the build. Do not invoke login or API-key configuration.

- [ ] **Step 4: Add the SSH stage**

  Install `openssh-server`, copy a container-specific `sshd_config`, create the runtime host-key directory, and leave process startup to the entrypoint.

- [ ] **Step 5: Build the image and verify the intended failure is resolved**

  Run:

  ```bash
  docker buildx bake alinux3-full --load
  ```

  Expected: image builds successfully and exposes `bash`, `zsh`, `vim`, `nvim`, `git`, `starship`, `claude`, `codex`, and `cursor-agent`.

- [ ] **Step 6: Commit the image build**

  ```bash
  git add containers/alinux3/Dockerfile containers/alinux3/versions.env docker-bake.hcl
  git commit -m "feat: add alinux3 development image"
  ```

### Task 3: Implement runtime admin UID/GID synchronization

**Files:**
- Create: `containers/alinux3/user-sync.sh`
- Create: `containers/alinux3/entrypoint.sh`

**Interfaces:**
- `user-sync.sh` accepts `DEV_USER`, `DEV_UID`, `DEV_GID`, and `DEV_HOME` from the environment and exits nonzero on unsafe UID/GID conflicts.
- `entrypoint.sh` calls user sync as root, initializes managed configuration, then uses `exec` to run the requested command as `admin`.

- [ ] **Step 1: Extend the failing tests for idempotency and conflict safety**

  Add tests for repeated startup, default values, an existing matching UID/GID, and refusal to modify an unrelated user occupying the requested UID.

- [ ] **Step 2: Run the focused tests and verify they fail**

  ```bash
  bash containers/alinux3/tests/run-docker-tests.sh
  ```

  Expected: the new identity tests fail because no runtime sync implementation exists.

- [ ] **Step 3: Implement minimal idempotent synchronization**

  The script must validate numeric UID/GID values, adjust the existing `admin` account only when safe, update the primary group, create or repair `/home/admin`, and never chown `/workspace` unless an explicit opt-in variable is set.

- [ ] **Step 4: Implement entrypoint privilege handling**

  Refuse to perform synchronization when the entrypoint is not root, support `bash`, `zsh`, `sshd`, and arbitrary commands, preserve signals with `exec`, and use an installed privilege-drop helper or `su` with a login shell to run development commands as `admin`.

- [ ] **Step 5: Run the focused tests and verify they pass**

  ```bash
  docker buildx bake alinux3-full --load
  bash containers/alinux3/tests/run-docker-tests.sh
  ```

- [ ] **Step 6: Commit runtime synchronization**

  ```bash
  git add containers/alinux3/user-sync.sh containers/alinux3/entrypoint.sh containers/alinux3/tests
  git commit -m "feat: synchronize admin identity at container startup"
  ```

### Task 4: Add Dev Container and docker run interfaces

**Files:**
- Create: `.devcontainer/devcontainer.json`
- Create: `scripts/devtools-container-run`
- Create: `containers/alinux3/README.md`

**Interfaces:**
- `.devcontainer/devcontainer.json` builds the `full` target and uses `remoteUser: admin` with `updateRemoteUserUID: true`.
- `scripts/devtools-container-run` accepts `--user`, `--uid`, `--gid`, `--workspace`, `--ssh`, and an image name, always starting the image entrypoint as root and passing runtime identity variables.

- [ ] **Step 1: Add CLI contract tests**

  Test `--help`, missing image handling, automatic host UID/GID selection, and that generated Docker arguments contain `--user root`, `DEV_UID`, and `DEV_GID`.

- [ ] **Step 2: Implement the wrapper**

  Keep argument parsing Bash 3.2-compatible, use `id -u` and `id -g` defaults, mount the current directory to `/workspace`, and use `exec docker run` so signals and exit codes propagate.

- [ ] **Step 3: Add Dev Container metadata**

  Configure the Dockerfile/build target, `remoteUser`, UID update, workspace folder, zsh terminal profile, and persistent volumes for `/home/admin/.claude`, `/home/admin/.codex`, and `/home/admin/.cursor` without embedding credentials.

- [ ] **Step 4: Document all three modes**

  Document Dev Container, wrapper-based Docker, raw Docker numeric UID, SSH startup, credential mounts, and why `docker run --user admin` does not perform runtime synchronization.

- [ ] **Step 5: Commit the interfaces**

  ```bash
  git add .devcontainer scripts/devtools-container-run containers/alinux3/README.md
  git commit -m "feat: add devcontainer and docker run interfaces"
  ```

### Task 5: Verify, lint, and integrate repository metadata

**Files:**
- Modify: `README.md`
- Modify: `terminal/README.md`
- Modify: `BUILD.bazel` or `containers/alinux3/BUILD.bazel` if required by test discovery

- [ ] **Step 1: Run shell syntax checks**

  ```bash
  bash -n containers/alinux3/entrypoint.sh
  bash -n containers/alinux3/user-sync.sh
  bash -n scripts/devtools-container-run
  ```

- [ ] **Step 2: Run image build and integration tests**

  ```bash
  docker buildx bake alinux3-full --load
  bash containers/alinux3/tests/run-docker-tests.sh
  docker buildx bake alinux3-ssh --load
  ```

- [ ] **Step 3: Run available repository checks**

  Run `bazel test //... --test_output=errors` when Bazel is installed; if unavailable, report it explicitly and run all available shell and Docker checks.

- [ ] **Step 4: Update documentation**

  Add the new `containers/`, `.devcontainer/`, and wrapper commands to the repository README while keeping existing host setup instructions unchanged.

- [ ] **Step 5: Inspect the final diff and commit documentation**

  ```bash
  git diff --check
  git status --short
  git add README.md terminal/README.md containers/alinux3/BUILD.bazel
  git commit -m "docs: document alinux3 development image"
  ```

## Verification Checklist

- [ ] `docker buildx bake alinux3-full --load` succeeds.
- [ ] Runtime startup with UID/GID 1001:1001 reports `admin` with matching numeric identity.
- [ ] A file created in a bind-mounted `/workspace` has the matching host UID/GID.
- [ ] Repeated startup does not alter unmanaged configuration.
- [ ] `docker buildx bake alinux3-ssh --load` succeeds.
- [ ] `git diff --check` is clean.
