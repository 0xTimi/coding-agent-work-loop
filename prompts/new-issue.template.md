你正在处理 GitHub issue #${ISSUE}（仓库 ${REPO}）。
标题：${TITLE}

## 工作环境
- 工作目录：`${WORKTREE}`（git worktree）
- 当前分支：`${BRANCH}`
- 依赖已经装好

## 工作流程（严格按此执行）
1. 读 issue 完整内容（含评论）：`gh issue view ${ISSUE} --repo ${REPO} --comments`
2. 评估：能否直接干？有歧义就 `gh issue comment ${ISSUE} --body "..."` 反问 + 把 label 标回 `${LABEL_PENDING_HUMAN}`，然后停 idle
3. 实现：改代码 → 必要的话补测试（TDD 优先）→ 跑 type-check / 相关测试 / lint → 通过为止
4. commit + `git push -u origin ${BRANCH}`
5. 开 PR：`gh pr create --base main --title "..." --body "..."`，body 必须含 `Closes #${ISSUE}`
6. 拿到 PR 编号 `<PR>` 后立即翻 label：
   - `gh pr edit <PR> --repo ${REPO} --add-label ${LABEL_PENDING_HUMAN}`
   - `gh issue edit ${ISSUE} --repo ${REPO} --add-label ${LABEL_PENDING_HUMAN} --remove-label ${LABEL_PENDING_AGENT}`
7. 完成后停在 idle，一句话回复：`PR #<PR> 已开，等待 review`

## 约束
- session 名是 CLI -n 已设的那个，不要自己 /rename
- 分支固定 `${BRANCH}`，不要改
- 不要碰其他 worktree
