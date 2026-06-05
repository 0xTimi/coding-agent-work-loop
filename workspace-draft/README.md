# workspace-draft — 多 repo workspace 改造草稿

把 luosky 的单-repo work-loop 改成 **workspace 级**（在 parent 发任务 → AI 自己分解到子 repo → 每个子 repo 各开 PR）的三份草稿。**纯草稿、供 review**，还没放进 GigleMDD、没碰 GitHub。

## 设计核心（一句话）
> worker 不再 worktree 单个 repo，而是 worktree **parent GigleMDD**，再用 `WORKTREE_SETUP_CMD` 钩子把**各子 repo 也 worktree 进去**，组成一个完整 workspace；Claude（带 parent CLAUDE.md）在里面跨 repo 协调，每个动过的子 repo 各开一个 PR。

**关键发现**：靠现成的 `WORKTREE_SETUP_CMD` 钩子就能装配，**connect create-worktree.sh 源码都不用改**。改动集中在 config + 一个装配脚本 + prompt。

## 三份草稿 → 最终落点

| 草稿文件 | 最终放哪 | 作用 |
|---|---|---|
| `coding-agent.config` | Mini 上的 `~/tim/work/GigleMDD/coding-agent.config`（gitignore，不进库）| REPO=parent + 子 repo 清单 + Mini 路径 + megan 身份 + 装配钩子 |
| `workspace-assembly.sh` | skill 里 `scripts/`（或 GigleMDD 项目级 `.agents/skills/.../`）| worktree 建好后，把各子 repo worktree 进 parent 工作区 |
| `new-issue.template.md` | GigleMDD 的 `.agents/skills/coding-agent-work-loop/prompts/`（项目级覆盖）| 设计阶段：跨 repo **分解提案**（同上游设计先行，只加多 repo）|
| `issue-comment.template.md` | 同上 | 开干阶段：确认后**每个动过的子 repo 各开一个 PR**（同上游决策树，只改 §A）|

## 与上游的差异（极小）
> **唯一改动 = 多子项目维度。其它全部照上游。**
- 工作流（设计先行两段式、label 流转、安全、Open Questions 格式）**完全不变**。
- worker 从"单 repo worktree"→"workspace（parent + 多子 repo worktree）"。
- 两个 prompt 各只加一处："设计阶段跨 repo 分解" + "开干阶段多 repo 各开 PR"。
- **没有** autonomous 默认、**没有** `plan-first` 标签（早先的误改已撤回）。

## 待定/待验证
- 装配脚本取 config 的方式（依赖 `CODING_AGENT_CONFIG` 在 env 里——systemd/launchd 路径成立；手动跑要 export）。
- 多 PR 合并顺序：v1 靠 PR body 写依赖、你手动按序合。
