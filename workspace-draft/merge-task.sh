#!/usr/bin/env bash
# merge-task.sh <issue> — 一键合并一个 parent issue 的所有子 repo PR（草稿）
#
# 做什么：
#   1. 在每个 WORKSPACE_SUBREPOS 子 repo 里找 head=agent/task-<issue> 的 open PR
#   2. 按 WORKSPACE_SUBREPOS 声明顺序（= 依赖顺序，后端在前）逐个 squash merge
#   3. 全合完 → 清理各子 repo worktree + parent worktree + tmux session
#      → parent issue 标 Done + close
#   4. 任一 PR 不可合（冲突/检查没过/合失败）→ 停，在 issue 留言，翻 pending/human
#
# 触发：daemon 看到 parent issue 有 pending/merge（待接进 agent-poll.sh），或手动跑。
# 注意：纯 gh/git 机械操作，不需要 AI worker。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

ISSUE="${1:?用法: merge-task.sh <issue-number>}"
MERGE_METHOD="${MERGE_METHOD:-squash}"   # squash | rebase | merge
TASK_BRANCH="$(branch_name "$ISSUE")"    # agent/task-<issue>

log "merge-task #$ISSUE: 方法=$MERGE_METHOD 分支=$TASK_BRANCH"
gh_label_flip "$ISSUE" --add "doing/merge" --remove "pending/merge" || true

# 兜底：一旦翻成 doing/merge 后脚本意外崩溃（非主动 exit），把 issue 拉回 pending/human，
# 不让它卡死在 doing/merge（那样 daemon 只认 pending/merge，永远不会再触发）。
# 主动错误分支会先置 HANDLED=1，故此 trap 只兜「没预料到的崩溃」。
HANDLED=0
_merge_trap() {
    local code=$?
    [ "$code" = 0 ] && return
    [ "$HANDLED" = 1 ] && return
    log "  ❌ merge-task #$ISSUE 意外崩溃 (exit=$code) → 拉回 pending/human"
    gh issue comment "$ISSUE" --repo "$REPO" --body \
      "⚠️ 一键合并脚本意外中断（exit=${code}），已停在安全状态。请检查后重新标 \`pending/merge\` 重试。" 2>/dev/null || true
    gh_label_flip "$ISSUE" --add "$LABEL_PENDING_HUMAN" --remove "doing/merge" || true
}
trap _merge_trap EXIT

# ── 1. 收集各子 repo 待合 PR（按 WORKSPACE_SUBREPOS 顺序）──
declare -a MERGE_PLAN=()   # 每项 "subrepo_name|pr_number"
while read -r name remote; do
    [ -z "${name:-}" ] && continue
    pr=$(gh pr list --repo "GigleAI/$name" --state open --head "$TASK_BRANCH" \
            --json number,mergeStateStatus --jq '.[0] // empty' 2>/dev/null || true)
    [ -z "$pr" ] && { log "  $name: 无 open PR（agent/task-${ISSUE}），跳过"; continue; }
    prnum=$(echo "$pr" | jq -r .number)
    state=$(echo "$pr" | jq -r .mergeStateStatus)
    log "  $name: PR #$prnum (mergeState=$state)"
    if [ "$state" != "CLEAN" ] && [ "$state" != "UNSTABLE" ]; then
        log "  ❌ $name PR #$prnum 不可合 (state=$state) → 终止"
        gh issue comment "$ISSUE" --repo "$REPO" --body \
          "⚠️ 一键合并中止：\`GigleAI/$name#$prnum\` 当前不可合并（状态 ${state}，可能有冲突/检查未过）。请人工处理后重标 \`pending/merge\`。"
        gh_label_flip "$ISSUE" --add "$LABEL_PENDING_HUMAN" --remove "doing/merge" || true
        HANDLED=1; exit 1
    fi
    MERGE_PLAN+=("$name|$prnum")
done <<< "$(printf '%s\n' "$WORKSPACE_SUBREPOS")"

if [ ${#MERGE_PLAN[@]} -eq 0 ]; then
    log "  没找到任何待合 PR"
    gh issue comment "$ISSUE" --repo "$REPO" --body "未找到 head=\`$TASK_BRANCH\` 的待合 PR。已无可合并项。"
    gh_label_flip "$ISSUE" --add "$LABEL_PENDING_HUMAN" --remove "doing/merge" || true
    exit 0
fi

# ── 2. 按序 squash merge ──
declare -a MERGED=()
for item in "${MERGE_PLAN[@]}"; do
    name="${item%%|*}"; prnum="${item##*|}"
    log "  merge GigleAI/$name#$prnum (--$MERGE_METHOD --delete-branch)"
    if gh pr merge "$prnum" --repo "GigleAI/$name" "--$MERGE_METHOD" --delete-branch 2>&1 | tee -a "$LOG_FILE" >&2; then
        MERGED+=("GigleAI/$name#$prnum")
    else
        log "  ❌ merge GigleAI/$name#$prnum 失败 → 终止（已合: ${MERGED[*]:-无}）"
        gh issue comment "$ISSUE" --repo "$REPO" --body \
          "⚠️ 一键合并中途失败于 \`GigleAI/$name#$prnum\`。已合并：${MERGED[*]:-无}。请人工处理后重标 \`pending/merge\`。"
        gh_label_flip "$ISSUE" --add "$LABEL_PENDING_HUMAN" --remove "doing/merge" || true
        HANDLED=1; exit 1
    fi
done

# ── 3. 清理 worktree + tmux ──
PARENT_WT="$(worktree_path "$ISSUE")"
SESS="$(tmux_session_name "$ISSUE")"
log "  cleanup: parent_wt=$PARENT_WT sess=$SESS"
tmux kill-session -t "$SESS" 2>/dev/null || true
# 先移除各子 repo 的 worktree（它们是子 repo 的 linked worktree）
while read -r name remote; do
    [ -z "${name:-}" ] && continue
    git -C "$PROJECT_ROOT/$name" worktree remove --force "$PARENT_WT/$name" 2>/dev/null || true
done <<< "$(printf '%s\n' "$WORKSPACE_SUBREPOS")"
# 再移除 parent worktree
git -C "$PROJECT_ROOT" worktree remove --force "$PARENT_WT" 2>/dev/null || true

# ── 4. parent issue 收尾 ──
_summary="$(printf '%s ' "${MERGED[@]}")"
gh issue comment "$ISSUE" --repo "$REPO" --body \
  "✅ 一键合并完成 (method=${MERGE_METHOD}): ${_summary}. worktree 已清理, issue 已关闭。"
gh_label_flip "$ISSUE" --add "$LABEL_DONE" \
  --remove "doing/merge" "$LABEL_PENDING_PR" "$LABEL_PENDING_HUMAN" "$LABEL_PENDING_AGENT" "$LABEL_AGENT_DOING" || true
gh issue close "$ISSUE" --repo "$REPO" 2>/dev/null || true

log "merge-task #$ISSUE done: 合并了 ${#MERGED[@]} 个 PR"
