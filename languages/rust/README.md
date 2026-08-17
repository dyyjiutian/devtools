# Rust 环境

通过 rustup 安装 stable Rust 工具链和常用 Cargo 工具。

~~~bash
bash languages/rust/setup.sh --help
bash languages/rust/setup.sh --dry-run
~~~

## Issues

### 2026-08-17 — macOS E2E 找不到 rustc

**表象**：`rust_ops_macos_e2e_test` 里 setup 看到宿主机 rustup 并更新成功，ops suite 报 rustc 不在 PATH。

**根因**：E2E 隔离 `HOME` 后 rustup 把 shim 写进临时 `~/.cargo`，而工具链仍在 runner 的 `CARGO_HOME`/`RUSTUP_HOME`；setup 在 `set -u` 下 source cargo env 会直接退出，ops suite 也找不到 rustc。

**解法**：`run_e2e_test.sh` 在改 `HOME` 前复用宿主机 `CARGO_HOME`/`RUSTUP_HOME`，并把该目录链到临时 HOME。`setup.sh` / ops suite source cargo env 时暂时 `set +u`。
