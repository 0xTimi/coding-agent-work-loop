#!/usr/bin/env bash
# workspace-assembly.sh — 由 WORKTREE_SETUP_CMD 调用（草稿）
#
# 背景：daemon 给一个 parent issue 建了 parent(GigleMDD) 的 worktree（cwd=该 worktree）。
# 本脚本把 WORKSPACE_SUBREPOS 列的每个子 repo 也 worktree 进来，凑成完整 workspace，
# 让 worker(Claude) 能跨 repo 改代码。
#
# 关键：parent 的 .gitignore 屏蔽了子 repo 目录 → 子 repo worktree 放进来不污染 parent git status。
#
# 运行环境前提：CODING_AGENT_CONFIG 在 env 里（systemd/launchd 注入；手动跑需 export）。
set -euo pipefail

# 取 config（PROJECT_ROOT / WORKSPACE_SUBREPOS / 子 repo 分支前缀 / bot 身份）
: "${CODING_AGENT_CONFIG:?need CODING_AGENT_CONFIG}"
# shellcheck disable=SC1090
source "$CODING_AGENT_CONFIG"

PARENT_WT="$PWD"                                   # cwd = parent worktree（create-worktree 已 -c 进来）
TASK_BRANCH="$(git -C "$PARENT_WT" rev-parse --abbrev-ref HEAD)"   # = agent/task-<N>，子 repo 复用

echo "[assembly] parent worktree=$PARENT_WT  branch=$TASK_BRANCH"

# 逐个子 repo 装配
while read -r name remote; do
    [ -z "${name:-}" ] && continue
    canonical="$PROJECT_ROOT/$name"               # Mini 上子 repo 的常驻 clone
    target="$PARENT_WT/$name"                      # workspace 里的挂载点

    # 子 repo 常驻 clone 不存在就先 clone（首次）
    if [ ! -d "$canonical/.git" ]; then
        echo "[assembly] clone $name ← $remote"
        git clone "$remote" "$canonical"
    fi

    git -C "$canonical" fetch origin --quiet

    # 已挂载就跳过（幂等）
    if [ -d "$target/.git" ] || git -C "$canonical" worktree list | grep -q "$target"; then
        echo "[assembly] $name 已挂载，跳过"
    else
        # 为这个 task 在子 repo 上开同名分支，worktree 进 workspace
        git -C "$canonical" worktree add -B "$TASK_BRANCH" "$target" origin/main
        echo "[assembly] + $name → $target ($TASK_BRANCH)"
    fi

    # 子 repo 也设 megan 身份（commit author）
    [ -n "${WORKTREE_GIT_USER_NAME:-}" ]  && git -C "$target" config user.name  "$WORKTREE_GIT_USER_NAME"
    [ -n "${WORKTREE_GIT_USER_EMAIL:-}" ] && git -C "$target" config user.email "$WORKTREE_GIT_USER_EMAIL"
done <<< "$(printf '%s\n' "$WORKSPACE_SUBREPOS")"

# 预先信任 worktree：claude 首次进新目录会弹"信任此文件夹"对话框，detached tmux
# 里没人按 → worker 卡死。--dangerously-skip-permissions 不覆盖这个。提前在
# ~/.claude.json 把本 worktree 标成已信任 + 已 onboarding，跳过对话框。
CLAUDE_JSON="$HOME/.claude.json"
if [ -f "$CLAUDE_JSON" ] && command -v jq >/dev/null 2>&1; then
    _tmp_cj="$(mktemp)"
    if jq --arg p "$PARENT_WT" \
        '.projects[$p].hasTrustDialogAccepted = true
         | .projects[$p].hasCompletedProjectOnboarding = true' \
        "$CLAUDE_JSON" > "$_tmp_cj" 2>/dev/null; then
        mv "$_tmp_cj" "$CLAUDE_JSON"
        echo "[assembly] 已预信任 worktree（跳过 claude 信任对话框）"
    else
        rm -f "$_tmp_cj"
        echo "[assembly] ⚠️ 预信任写入失败（claude 可能会弹信任框）"
    fi
fi

# 给 worker 留一份 workspace 清单（prompt 里引用）
{
    echo "# WORKSPACE（本 task 自动生成）"
    echo "task 分支: $TASK_BRANCH"
    echo "可改的子 repo（各自独立 git，改完各自 commit/push/开 PR）："
    while read -r name remote; do
        [ -z "${name:-}" ] && continue
        echo "  - ./$name   (GigleAI/$name)"
    done <<< "$(printf '%s\n' "$WORKSPACE_SUBREPOS")"
} > "$PARENT_WT/WORKSPACE.md"

echo "[assembly] done. 清单见 $PARENT_WT/WORKSPACE.md"
