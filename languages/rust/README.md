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

**解法**：`run_e2e_test.sh` 在 `CARGO_HOME` 仍为空且隔离 HOME 无 `.cargo` 时，用 `rustup which --toolchain stable rustc` 解析真实工具链 bin，把 rustc/cargo 逐个链进 `$HOME/.cargo/bin` 并设 `CARGO_HOME=$HOME/.cargo`。查找 PATH 需带上 Homebrew 目录（bazel 会净化测试 PATH，rustup 在 `/opt/homebrew/bin`）；只链单个工具而非整个 bin 目录，避免后续 `rustup update` 往 `CARGO_HOME/bin` 写 shim 时覆盖真实工具链二进制。`e2e_runner_suite.sh` 增加对应契约断言。

### 2026-11-16 — 预装 rustup 但没有 ~/.cargo 时仍找不到 rustc

**表象**：`rust_ops_macos_e2e_test` 里 setup 报 `rustup 已安装`、`stable 工具链已更新`，ops suite 仍
`FAIL: rustc not on PATH after setup`。日志中 `CARGO_HOME=` 为空、`RUSTUP_HOME=/Users/runner/.rustup`，
且 `ls $HOME/.cargo/bin` 报 No such file or directory。

**根因**：macos-26 runner 镜像预装了 rustup，只有 `~/.rustup` 而没有 `~/.cargo`。`install_rustup` 的
「已安装」分支只跑 `rustup update stable` 就 return，从不补建 `$CARGO_HOME/bin` 下的 rustc/cargo 代理，
也不设置 default toolchain；2026-08-17 的「复用宿主 CARGO_HOME 并软链」此时无目录可复用。
`~/.cargo/env` 同样不存在，写进 rc 的 `source "$HOME/.cargo/env"` 是空操作。

**进一步根因（第一次修复后 CI 仍红）**：rustup 只在安装/切换工具链时写代理。runner 上 stable 已经是
default，`rustup default stable` 是 **no-op：退出码 0 但不写任何代理**，因此全新的 `CARGO_HOME/bin`
依旧不存在（CI 日志里先打印「代理已就绪」，随后 `ls` 仍报 No such file or directory）。

**解法**：`setup.sh` 在已安装分支补 `ensure_cargo_proxies` 与 `ensure_cargo_env_file`，并把 cargo bin 加入 PATH：

1. 代理或 active toolchain 缺失时先跑 `rustup default stable`；
2. 跑完仍没有 `rustc`/`cargo` 代理时，用 `rustup which <tool>` 定位当前工具链的真实二进制并建链
   （指向 stable 通道目录，原地更新，不锁版本），覆盖 rustc/cargo/rustdoc/rustfmt/clippy-driver；
3. `env` 缺失时写等价 POSIX sh PATH 片段，已有 `env` 不覆盖。

`run_e2e_test.sh` 对「有 `~/.rustup` 但无 `~/.cargo`」的宿主把 `CARGO_HOME` 指向隔离 HOME，
让代理落在 ops suite 查找的位置。健康的预装环境不会被重复 `rustup default`。

**验证**：

~~~bash
bazel test --config=l1 //languages/rust:rust_linux_ubuntu_test //languages/rust:rust_macos_test
# L1 用 fake rustup 覆盖三种预装形态：default 会写代理 / default 是 no-op（runner 实况）/ 已健康
# 真实预装 rustup 的环境由 CI 的 rust_ops_macos_e2e_test 覆盖
~~~

### 2026-08-17 — macOS E2E 找不到 rustc

**表象**：`rust_ops_macos_e2e_test` 里 setup 看到宿主机 rustup 并更新成功，ops suite 报 rustc 不在 PATH。

**根因**：E2E 隔离 `HOME` 后 rustup 把 shim 写进临时 `~/.cargo`，而工具链仍在 runner 的 `CARGO_HOME`/`RUSTUP_HOME`；setup 在 `set -u` 下 source cargo env 会直接退出，ops suite 也找不到 rustc。

**解法**：`run_e2e_test.sh` 在改 `HOME` 前复用宿主机 `CARGO_HOME`/`RUSTUP_HOME`，并把该目录链到临时 HOME。`setup.sh` / ops suite source cargo env 时暂时 `set +u`。
