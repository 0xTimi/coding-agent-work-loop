#!/usr/bin/env bash
# 给指定 issue 编号创建 worktree：分支 + 装依赖 + 复制 gitignored 配置文件。
# 用法：
#   scripts/create-worktree.sh <issue-number> [base-branch]
# 例：
#   scripts/create-worktree.sh 42 main
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

ISSUE="${1:?need issue number}"
BASE_BRANCH="${2:-main}"

BRANCH="$(branch_name "$ISSUE")"
WORKTREE_DIR="$(worktree_path "$ISSUE")"

log "create-worktree: issue=$ISSUE branch=$BRANCH dir=$WORKTREE_DIR base=$BASE_BRANCH"

cd "$PROJECT_ROOT"

# 1. 分支
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    log "  branch $BRANCH 已存在，复用"
elif git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    log "  origin/$BRANCH 已存在，签出"
    git fetch origin "$BRANCH"
else
    log "  新建分支 $BRANCH ← origin/${BASE_BRANCH}（先 fetch 取最新，避免基于陈旧本地 main）"
    git fetch origin "$BASE_BRANCH" --quiet
    git branch "$BRANCH" "origin/$BASE_BRANCH"
fi

# 2. worktree
if [ -d "$WORKTREE_DIR" ]; then
    log "  worktree 目录已存在：${WORKTREE_DIR}（跳过创建）"
else
    mkdir -p "$WORKTREE_BASE"
    git worktree add "$WORKTREE_DIR" "$BRANCH"
fi

# 3a. 给 worktree 设独立的 git 身份（worker commit 用 bot 而非 user）
if [ -n "${WORKTREE_GIT_USER_NAME:-}" ] || [ -n "${WORKTREE_GIT_USER_EMAIL:-}" ]; then
    [ -n "${WORKTREE_GIT_USER_NAME:-}" ] && git -C "$WORKTREE_DIR" config user.name "$WORKTREE_GIT_USER_NAME"
    [ -n "${WORKTREE_GIT_USER_EMAIL:-}" ] && git -C "$WORKTREE_DIR" config user.email "$WORKTREE_GIT_USER_EMAIL"
    log "  worker identity: $(git -C "$WORKTREE_DIR" config user.name) <$(git -C "$WORKTREE_DIR" config user.email)>"
fi

# 3b. 复制 COPY_TO_WORKTREE 列出的本地配置（默认含 .env 和 .claude/settings.local.json）
for rel in ${COPY_TO_WORKTREE:-}; do
    src="$PROJECT_ROOT/$rel"
    dst="$WORKTREE_DIR/$rel"
    if [ -f "$src" ]; then
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        log "  复制 $rel"
    fi
done

# 3c. 长程任务护栏（opt-in：issue 打 `long-horizon` label 才装）。
# 装一个 command 型 Stop hook：只要 parent issue 还挂 `doing/agent`，就不许
# worker 停——它必须先交接（开 PR→pending/PR，或留言→pending/human 翻掉
# doing/agent）。挡住「大任务半途停」+「闷头退出留下 doing/agent 僵尸名额」。
# 普通任务不打这 label → 无 hook，行为照旧（想停就停）。
REPO="${REPO:-GigleAI/GigleMDD}"
if command -v gh >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 \
   && gh issue view "$ISSUE" --repo "$REPO" --json labels --jq '[.labels[].name]' 2>/dev/null | grep -q '"long-horizon"'; then
    SETTINGS="$WORKTREE_DIR/.claude/settings.local.json"
    mkdir -p "$(dirname "$SETTINGS")"
    HOOK_CMD="L=\$(gh issue view ${ISSUE} --repo ${REPO} --json labels --jq '[.labels[].name]|join(\",\")' 2>/dev/null) || exit 0; case \",\$L,\" in *\",doing/agent,\"*) echo 'Issue #${ISSUE} 仍是 doing/agent：本阶段还没交接，先完成并翻 label（开 PR→pending/PR，或留言→pending/human）再停。' >&2; exit 2;; *) exit 0;; esac"
    base='{}'; [ -f "$SETTINGS" ] && base="$(cat "$SETTINGS" 2>/dev/null || echo '{}')"
    if printf '%s' "$base" | jq --arg c "$HOOK_CMD" '.hooks.Stop = [{"hooks":[{"type":"command","command":$c}]}]' > "$SETTINGS.tmp" 2>/dev/null; then
        mv "$SETTINGS.tmp" "$SETTINGS"
        log "  long-horizon：已装 Stop hook（doing/agent 期间禁止 stop）"
    else
        rm -f "$SETTINGS.tmp"
        log "  ⚠️ 写 Stop hook 失败，跳过（不阻塞）"
    fi
fi

# 4. 跑 setup 命令
if [ -n "${WORKTREE_SETUP_CMD:-}" ] && [ "${WORKTREE_SETUP_CMD}" != ":" ]; then
    log "  跑 WORKTREE_SETUP_CMD: $WORKTREE_SETUP_CMD"
    (cd "$WORKTREE_DIR" && eval "$WORKTREE_SETUP_CMD") || {
        log "  ⚠️ WORKTREE_SETUP_CMD 失败（继续，不阻塞）"
    }
fi

log "create-worktree done: $WORKTREE_DIR"
echo "$WORKTREE_DIR"
