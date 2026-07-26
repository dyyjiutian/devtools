# Agent 工具

本目录用于管理 Claude、Codex 和 Cursor Agent 的安装、配置与可移植实践。

## 子模块

- agents/claude：Claude Code 安装与渠道配置。
- agents/codex：Codex CLI 安装、权限和渠道配置。
- agents/cursor-agent：Cursor Agent CLI 安装与权限同步。
- agents/cookbook：个人编程习惯与经验配方（skills / commands 等），可同步给 Agent 消费。

运行时安装与渠道配置放在各 Agent 子目录；跨 Agent 的个人配方放在 `cookbook/`，用其 `setup.sh sync` 链到本机 skills 目录。
