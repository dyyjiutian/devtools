---
name: dev-verify
description: >-
  Use as the verification gate in dev-loop after execute (and simply in
  full mode). Triggers: verify, TDD, 补测, 验证, verification, regression, test.
---

# Dev Verify

两种模式共用的验证门禁（不只单测：含脚本检查、dry-run、场景验证等）。完成前必须有证据；缺工具则说明未跑，不得假称通过。

优先执行设计阶段已确认的验证策略（full：design `## 测试要点`；simple：ask 结论）。不要用更弱的检查悄悄降级。

## Strategy

| 改动类型 | 默认策略（若设计未另有约定） |
|---|---|
| 行为 / 逻辑 / bugfix | TDD：先写失败测试 → 最小实现 → 转绿 |
| 纯配置 / 文档 / 幂等脚本 | 实现后最小验证（`bash -n`、`--help`、相关回归、`--dry-run`） |

若设计要求场景/功能测试、mock、特定环境或兼容性/性能检查：按设计执行；缺环境则如实说明并与用户确认是否缩小范围。

## Evidence

按设计与改动范围选择最小充分检查，例如：

```bash
git diff --check
bash -n path/to/script.sh
bash agents/cookbook/tests/skills_structure_test.sh
```

涉及安装器时优先 `--help` / `--dry-run`，不要为验证跑真实安装（除非设计明确要求且用户同意）。

## Done criteria

- 设计阶段列出的测试要点已覆盖或已说明未跑原因
- 相关测试/检查已执行并记录结果
- 失败已修复或已向用户说明阻塞
- 未宣称“全部通过”若实际跳过了关键检查
