PR #${PR} 有新评论，请处理。

## 流程
1. 读最新评论：`gh pr view ${PR} --repo ${REPO} --comments`（最末一段是最新）
2. 判断评论类型：
   - **讨论 / 问问题** → `gh pr comment ${PR} --body "<回答>"`
   - **要求改代码** → 改 → type-check + 相关测试通过 → `git commit -m "..."` + `git push` → `gh pr comment ${PR} --body "已修复：<简述>"`
   - **不明确 / 需要更多信息** → `gh pr comment ${PR} --body "<澄清问题>"`（label 保持 ${LABEL_PENDING_HUMAN}，等用户答）
3. 翻 label：`gh pr edit ${PR} --repo ${REPO} --add-label ${LABEL_PENDING_HUMAN} --remove-label ${LABEL_PENDING_AGENT}`
4. 完成后停在 idle，一句话总结。

## 上下文
- 仓库：${REPO}
- 分支：${BRANCH}（当前工作目录）
- 关联 issue：#${ISSUE_N}
