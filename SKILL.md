---
name: coding-agent-workflow
description: 用 GitHub label 驱动本机 Claude Code agent 处理 issue/PR，daemon 自动监听并派工。包含 setup（一次部署到某个项目）、status（查 daemon 状态）、disable（关闭某项目的 daemon）等命令
---

# coding-agent-workflow

把 GitHub issue / PR 评论变成你本机 Claude Code agent 的输入输出。一个 systemd timer + 几个 shell 脚本 + 两个 GitHub label，让你通过 GitHub 网页（或 iOS gh app）直接跟 agent 沟通。

## 触发方式

用户在 Claude Code 里输入 `/coding-agent-workflow <command>` 或自然语言要求时调用本 skill。常见请求：

- 「帮我把这个 daemon 装到 X 项目」→ 调 `setup` 流程
- 「coding agent 现在状态如何」→ 调 `status` 流程
- 「关掉 X 项目的 coding agent」→ 调 `disable` 流程

## 你（Claude）调用本 skill 时该做什么

### setup（部署到一个 host project）

用户给你一个 host project 路径（如 `~/github/myproject`）。你的步骤：

1. 验证路径存在且是 git 仓库（`.git` 在）
2. 检查依赖：`git`、`gh`（已 `gh auth login`）、`tmux`、`jq`、`flock`、`claude`、`systemctl` 都能 `command -v` 到
3. 跑：
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/setup.sh" <host-project-path>
   ```
   `$CLAUDE_PLUGIN_ROOT` 是当前 skill 的目录（Claude Code 自动注入）。如果没有，回退到 `~/.claude/skills/coding-agent-workflow`。
4. setup.sh 跑完后会打印下一步指南，原文转给用户

### status

用户要看状态。你的步骤：

1. `systemctl --user list-timers 'coding-agent-poll@*' --no-pager` — 看 timer 健康
2. `systemctl --user list-units 'coding-agent-poll@*.service' --no-pager` — 看最近一次执行
3. 对每个已注册的 `~/.config/coding-agent-workflow/*.conf`：
   - `tail -20 $STATE_DIR/poll.log`（从 conf 读 STATE_DIR）
   - `gh issue list --repo $REPO --label pending/agent` + `gh pr list --repo $REPO --label pending/agent`
4. 汇总报告给用户

### disable

用户要停某项目。你的步骤：

1. 确认 instance 名（`systemctl --user list-timers 'coding-agent-poll@*'`）
2. `systemctl --user disable --now coding-agent-poll@<key>.timer`
3. 可选：删除 `~/.config/systemd/user/coding-agent-poll@<key>.{service,timer}` 实例符号链接（如果是真单元文件不动）
4. 可选：删除 `~/.config/coding-agent-workflow/<key>.conf`
5. 报告

## 项目内不需要的文件

setup 跑完后，host project 工作树里**只多两个东西**：

1. 一行 `.gitignore`（排除 `coding-agent.config`）
2. 一个 `coding-agent.config`（gitignored，配置）

脚本、systemd unit、state、日志都在 host 项目之外（skill 目录 + `~/.config/` + `~/.local/state/`）。

## 详细架构

见同目录 [README.md](README.md)。

## 文件清单

- `setup.sh` — bootstrap 一个 host project
- `scripts/` — daemon + dispatch 脚本（不复制到 host project）
- `prompts/` — worker 初始 prompt 模板（可被 host project 的 `.coding-agent/prompts/` 覆盖）
- `systemd/` — `coding-agent-poll@.service/.timer` 模板单元，setup 时复制到 `~/.config/systemd/user/`
- `coding-agent.config.example` — 配置模板
