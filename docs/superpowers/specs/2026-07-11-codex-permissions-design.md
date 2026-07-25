# Codex 权限配置优化设计

## 目标

在仓库现有的 Codex 安装、多渠道切换和配置同步能力上，增量加入一套可移植、可重复同步的权限配置：除明确的高风险删除和通用外传命令外，其余命令默认允许执行。敏感命令不永久禁止，而是在每次执行前要求用户确认。

## 权限边界

- 默认允许命令执行、工作区外写入和网络访问。
- `rm` 命令族执行前提示确认，覆盖 `rm -rf` 及参数变体，避免仅匹配某一种参数顺序而被绕过。
- 通用文件传输和直接数据发送命令执行前提示确认：`scp`、`sftp`、`rsync`、`curl`、`wget`、`nc`、`ncat`、`socat`。
- `git push`、`npm` 及其他正常开发和发布命令不纳入敏感规则。
- 敏感命令经用户批准后可以执行，不使用永久禁止策略。

Codex 的原生 `prefix_rule` 只支持命令参数前缀匹配，不能像 Claude 配置一样对任意参数位置使用通配符。因此，本设计对敏感命令族整体设置 `prompt`。这会让本地 `rsync`、`curl` 下载等非外传用法也触发确认，但可以避免参数顺序或命令选项造成的漏检。

## 文件结构

```text
codex/
├── README.md
├── setup.sh
└── config/
    ├── AGENTS.md
    ├── config.toml
    ├── profiles/
    └── rules/
        └── default.rules
```

### `config/config.toml`

现有配置模板保留模型、provider 等示例，只修改与本目标直接相关的两个默认键：

```toml
approval_policy = "on-request"
sandbox_mode = "danger-full-access"
```

`danger-full-access` 取消默认文件系统和网络沙箱限制；`on-request` 保留由敏感规则触发的交互审批能力。

### `config/rules/default.rules`

每个敏感命令族使用 `prefix_rule(..., decision = "prompt")`。规则包含清晰的 `justification`，并使用 `match` 示例作为加载时校验，方便 `codex execpolicy check` 验证行为。

规则不添加覆盖所有命令的 `allow` 前缀；默认放行由 `danger-full-access` 提供，避免维护庞大的命令白名单。

### `setup.sh`

在现有 `setup.sh sync` 命令上增加权限同步，保留安装、登录、渠道切换、模型配置和 `AGENTS.md` 同步等现有行为：

1. 执行现有的渠道托管块和 `AGENTS.md` 同步流程。
2. 创建 `~/.codex/rules`。
3. 若 `~/.codex/config.toml` 已存在，在修改权限键前创建带时间戳的备份。
4. 只更新顶层 `approval_policy` 和 `sandbox_mode`，保留现有托管块、模型、插件、MCP、通知等配置。
5. 将仓库规则以独立的带标记托管块合并到 `~/.codex/rules/default.rules`；替换旧托管块，保留用户已有规则，并避免重复写入。
6. 输出重启 Codex 后生效的提示。

合并实现不得依赖平台特有的 TOML 编辑器。脚本应使用当前环境普遍可用的 shell 工具，并对顶层目标权限键做受限、可预测的替换；不能误改同名注释、嵌套配置或无关配置段。

## 数据流与失败处理

```text
仓库权限模板 ──┐
               ├─ setup.sh sync ─→ 备份 ─→ ~/.codex/config.toml
本机现有配置 ──┘                         └→ ~/.codex/rules/default.rules
```

- 模板缺失、目标文件不可写或合并失败时，脚本立即退出并保留备份。
- 若 Codex CLI 未安装，脚本可以同步文件，但应提示无法执行规则行为校验。
- 已存在的用户规则不得删除或改写；只有本仓库标记的规则块可被更新。
- 重复执行 `sync` 后，配置键和托管规则不得重复。

## 验证策略

- 使用可用的 TOML 解析器验证模板与同步后的配置语法。
- 使用 `bash -n codex/setup.sh` 验证脚本语法。
- 在临时 `HOME` 中执行两次 `sync`，确认备份、保留既有配置和幂等性。
- 使用 `codex execpolicy check` 验证 `rm`、`scp`、`curl` 等命令得到 `prompt`。
- 验证 `git push`、`npm install`、`ls` 等普通命令不匹配敏感规则。
- 检查 Git diff，确保不触碰现有 `notify/` 未提交改动。

## 非目标

- 不修改用户现有模型、provider、插件、MCP、通知或功能开关。
- 不重构或替换现有 Codex 安装、渠道切换和 API Key 管理逻辑。
- 不安装或卸载 Codex。
- 不为 `git push`、包发布或 GitHub 写操作增加审批。
- 不实现自定义命令解析 Hook。
