# Rust 环境

通过 rustup 安装 stable Rust 工具链和常用 Cargo 工具。

~~~bash
bash languages/rust/setup.sh --help
bash languages/rust/setup.sh --dry-run
~~~

## Issues

### 2026-11-19 — macos-26 runner 上 macOS E2E 仍找不到 rustc

**表象**：`rust_ops_macos_e2e_test` Exit 1，`FAIL: rustc not on PATH after setup`，`ls $HOME/.cargo/bin: No such file or directory`；suite 环境里 `CARGO_HOME=` 为空、`RUSTUP_HOME=/Users/runner/.rustup`。其他 PR 同样失败。

**根因**：2026-08-17 的修复假设宿主 cargo home 在 `$HOST_HOME/.cargo`。GitHub macos-26 镜像只预装 `RUSTUP_HOME`（`/Users/runner/.rustup`），没有 `/Users/runner/.cargo`，于是 `run_e2e_test.sh` 的 `CARGO_HOME` 复用分支不触发，隔离 HOME 里没有 `.cargo/bin`，真正的工具链 bin 也没进 PATH。

**解法**：`run_e2e_test.sh` 在 `CARGO_HOME` 仍为空且隔离 HOME 无 `.cargo` 时，用 `rustup which rustc` 解析真实工具链 bin，把它链成 `$HOME/.cargo/bin` 并设 `CARGO_HOME=$HOME/.cargo`。`e2e_runner_suite.sh` 增加对应契约断言。

### 2026-08-17 — macOS E2E 找不到 rustc

**表象**：`rust_ops_macos_e2e_test` 里 setup 看到宿主机 rustup 并更新成功，ops suite 报 rustc 不在 PATH。

**根因**：E2E 隔离 `HOME` 后 rustup 把 shim 写进临时 `~/.cargo`，而工具链仍在 runner 的 `CARGO_HOME`/`RUSTUP_HOME`；setup 在 `set -u` 下 source cargo env 会直接退出，ops suite 也找不到 rustc。

**解法**：`run_e2e_test.sh` 在改 `HOME` 前复用宿主机 `CARGO_HOME`/`RUSTUP_HOME`，并把该目录链到临时 HOME。`setup.sh` / ops suite source cargo env 时暂时 `set +u`。
