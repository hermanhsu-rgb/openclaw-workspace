#!/bin/bash
# 默认日志钩子: on_error
EVENT="$1"
SESSION_ID="$2"
ERROR_TYPE="$3"
ERROR_MSG="$4"
CONTEXT="$5"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] Session: $SESSION_ID, Type: $ERROR_TYPE, Msg: $ERROR_MSG" >> ~/.openclaw/agent_loop/hooks/logs/errors.log
