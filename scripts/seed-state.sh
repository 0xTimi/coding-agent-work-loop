#!/usr/bin/env bash
# 首次部署时跑：seed state.json，把当前所有 open PR 的最新 comment ID 设为「已见」，
# 避免 daemon 启动后把历史评论当新评论 re-dispatch。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

STATE_FILE="$STATE_DIR/state.json"
seen_pr='{}'
seen_issue='{}'

echo "== seed PR latest-comment ids =="
pr_numbers=$(gh pr list --repo "$REPO" --state open --json number --jq '.[].number')
for pr in $pr_numbers; do
    latest=$(gh api "repos/$REPO/issues/$pr/comments" --jq '.[-1].id // 0' 2>/dev/null || echo 0)
    seen_pr=$(echo "$seen_pr" | jq ".\"$pr\" = $latest")
    echo "  PR #$pr -> last comment id $latest"
done

echo "== seed Issue latest-comment ids（避免老 issue 的历史 comment 被当新事件触发）=="
issue_numbers=$(gh issue list --repo "$REPO" --state open --json number --jq '.[].number')
for is in $issue_numbers; do
    latest=$(gh api "repos/$REPO/issues/$is/comments" --jq '.[-1].id // 0' 2>/dev/null || echo 0)
    seen_issue=$(echo "$seen_issue" | jq ".\"$is\" = $latest")
    echo "  Issue #$is -> last comment id $latest"
done

jq -n --argjson p "$seen_pr" --argjson i "$seen_issue" \
    '{seen_comments: $p, seen_issue_comments: $i}' > "$STATE_FILE"
echo "Seeded $STATE_FILE"
