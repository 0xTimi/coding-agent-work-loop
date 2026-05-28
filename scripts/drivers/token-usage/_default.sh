#!/usr/bin/env bash
# Token usage driver: fallback default
#
# 用法: bash _default.sh <start_epoch>
#   start_epoch: 当次任务开始时间的 epoch（worker 在发 comment 时算）
#
# stdout: 单行字符串描述 token 用量（如 "in 12k · cache 95k · out 3.4k"），
#         或空字符串表示拿不到——worker prompt 看到空就落"未知"兜底
#
# 这里是 fallback 实现：未知 agent / driver 没实现自己 token usage 时用，
# 直接输出空，让 worker prompt 兜底分支落"未知"。
#
# 实现新 driver 的 token usage 时，在本目录加 <agent>.sh（同名于 _common.sh
# source_driver 选的 driver 名），dispatch 会优先选它而不是这个 _default。
exit 0
