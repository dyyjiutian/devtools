---
name: dev-test
description: >-
  Use as the verification gate in dev-pipeline after exec (and simply in
  full mode). Triggers: TDD, 补测, 验证, verification, regression.
---

# Dev Test

两种模式共用的测试门禁。完成前必须有证据；缺工具则说明未跑，不得假称通过。

## Strategy

| 改动类型 | 策略 |
|---|---|
| 行为 / 逻辑 / bugfix | TDD：先写失败测试 → 最小实现 → 转绿 |
| 纯配置 / 文档 / 幂等脚本 | 实现后最小验证（`bash -n`、`--help`、相关回归、`--dry-run`） |

## Evidence

按改动范围选择最小充分检查，例如：

```bash
git diff --check
bash -n path/to/script.sh
bash agents/cookbook/tests/skills_structure_test.sh
```

涉及安装器时优先 `--help` / `--dry-run`，不要为验证跑真实安装。

## Done criteria

- 相关测试/检查已执行并记录结果
- 失败已修复或已向用户说明阻塞
- 未宣称“全部通过”若实际跳过了关键检查
