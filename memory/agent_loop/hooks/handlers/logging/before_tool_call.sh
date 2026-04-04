#!/bin/bash
# 默认日志钩子: before_tool_call
EVENT="$1"
SESSION_ID="$2"
TOOL_NAME="$3"
ARGS="$4"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$EVENT] Session: $SESSION_ID, Tool: $TOOL_NAME" >> ~/.openclaw/agent_loop/hooks/logs/tool_calls.log
