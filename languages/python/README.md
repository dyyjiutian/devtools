# Python 环境

通过 pyenv 和 uv 初始化 Python 运行时与常用开发工具。

~~~bash
bash languages/python/setup.sh --help
bash languages/python/setup.sh --dry-run
~~~

脚本会在修改 Shell 配置前使用标记，重复执行不会重复追加。pyenv 初始化会写入
`~/.bashrc` 与 `~/.zshrc`（按文件存在情况），确保 bash / zsh 用户都能生效。

## Issues

### 2026-11-18 — pyenv 初始化只写 ~/.zshrc，bash 登录 shell 里 Python 不生效

**表象**：在未安装 zsh、登录 shell 为 bash 的机器上运行 `setup.sh` 后，新终端里
`python` 仍是系统旧版本（如 3.6.8），pyenv shims 不生效。

**根因**：`configure_pyenv_shell` 按优先级只选一个 rc 文件——只要 `~/.zshrc`
存在（哪怕是历史遗留文件），初始化就只写 zshrc，而用户实际使用的是 bash。

**解法**：改为向 `~/.bashrc` 和 `~/.zshrc` 都写入带标记的管理块（与 go/java
模块一致），已写入的文件跳过，保证幂等；同时补上 DRY_RUN 预览分支，
`--dry-run` 不再实际写 rc。回归：`bazel test //languages/python/...`。
