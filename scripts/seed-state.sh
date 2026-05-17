#!/usr/bin/env bash
# 首次部署时跑：seed state.json，把当前所有 open PR 的最新 comment ID 设为「已见」，
# 避免 daemon 启动后把历史评论当新评论 re-dispatch。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

STATE_FILE="$STATE_DIR/state.json"
seen='{}'

pr_numbers=$(gh pr list --repo "$REPO" --state open --json number --jq '.[].number')
for pr in $pr_numbers; do
    latest=$(gh api "repos/$REPO/issues/$pr/comments" --jq '.[-1].id // 0' 2>/dev/null || echo 0)
    seen=$(echo "$seen" | jq ".\"$pr\" = $latest")
    echo "  PR #$pr -> last comment id $latest"
done

echo "{\"seen_comments\":$seen}" | jq . > "$STATE_FILE"
echo "Seeded $STATE_FILE"
