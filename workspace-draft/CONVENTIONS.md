# 使用约定速查（operator 视角）

这套多 repo work-loop 怎么用、有哪些"打个标记/标签 AI 就懂"的约定。**给操作者（开 issue、审 PR 的人）看的。**

## 整体流程：你只在 3 个点动手，其余全自动

```
① 你：开 issue（parent 仓库 GigleAI/GigleMDD）+ 标 pending/agent
       └→ daemon 60s 内自动接管 → AI 出「跨 repo 设计方案」+ Open Questions → pending/human
② 你：勾选 Open Questions（可选）+ 标回 pending/agent
       └→ AI 跨子 repo 实现 → 每个动过的子 repo 各开一个 PR → pending/PR
③ 你：到各子 repo 审 PR 代码 + 给 parent issue 标 pending/merge
       └→ daemon 自动按序 squash 合并所有子 PR → 清理 → issue 标 Done + 关闭
```

> 任务（issue）永远在 **parent GigleMDD**；代码 PR 在**各子 repo**（Gateway/Web…），审代码要去子 repo。

## 约定一览

### 🏷️ 标签（label）= 状态机 = 接力棒
| label | 谁设 | 含义 / 该谁动 |
|---|---|---|
| `pending/agent` | **你** | "AI 接手干"（开 issue 时设、或确认设计后重设）|
| `doing/agent` | daemon | AI 正在跑（别碰）|
| `pending/human` | AI | 等你审设计/拍板 |
| `pending/PR` | AI | PR 开好了，去各子 repo 审 |
| `pending/merge` | **你** | "把所有子 PR 一键合并"（审完 PR 后设）|
| `doing/merge` | daemon | 正在合并 |
| `Done` | daemon | 合并+清理完，结案 |

口诀：**`pending/xxx` = 轮到 xxx 动**。你只管设 `pending/agent` 和 `pending/merge` 两个。

### ✍️ 标题：AI 帮你起
开 issue 时标题填这些**任一**（去空格、不分大小写、**半角全角都算**），AI 就**据正文自动起标题**：

> `.`　`。`　`?`　`？`　`tbd`　`auto`

填**其它任何标题** → AI **绝不碰**，尊重你写的。

### ☑️ Open Questions（设计方案里的勾选题）
AI 在设计方案里给的待澄清问题，用 checkbox：
- **勾 1 个** = 拍板按它
- **不勾** = 走题尾标的「默认」
- **勾多个** = 想再讨论（AI 下轮会反问）

勾完记得把 label 改回 `pending/agent` 才会触发开干（勾选本身不触发）。

## 基础设施备忘（不常用，出问题时翻）
- daemon 跑在 **mac-mini（megan0x-eth 身份）**，launchd 常驻、每 60s 轮询。
- worker = mac-mini 上的 Claude Code（已登录）；一个 task = 一个 tmux `gigle-task<N>` = 一个 workspace 目录（含各子 repo worktree）。
- 看 worker 实时干活（只读）：`ssh mac-mini-cloudf 'tail -f ~/.local/state/coding-agent-gigle/sessions/gigle-task<N>.log'`
