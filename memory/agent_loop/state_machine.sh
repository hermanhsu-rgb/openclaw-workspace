#!/bin/bash
# state_machine.sh - OpenClaw Agent 状态机实现
# 基于 Claude Code 架构，支持状态持久化和断点恢复

STATE_MACHINE_DIR="/root/.openclaw/agent_loop/state_machine"
STATE_DB="$STATE_MACHINE_DIR/states.db"
CHECKPOINT_DIR="$STATE_MACHINE_DIR/checkpoints"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 初始化状态机
init_state_machine() {
    mkdir -p "$STATE_MACHINE_DIR" "$CHECKPOINT_DIR"
    
    # 创建 SQLite 数据库
    sqlite3 "$STATE_DB" << 'EOF'
CREATE TABLE IF NOT EXISTS state_sessions (
    session_id TEXT PRIMARY KEY,
    current_state TEXT DEFAULT 'IDLE',
    previous_state TEXT,
    context TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    retry_count INTEGER DEFAULT 0,
    metadata TEXT
);

CREATE TABLE IF NOT EXISTS state_transitions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT,
    from_state TEXT,
    to_state TEXT,
    transition_name TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata TEXT,
    FOREIGN KEY (session_id) REFERENCES state_sessions(session_id)
);

CREATE TABLE IF NOT EXISTS state_checkpoints (
    checkpoint_id TEXT PRIMARY KEY,
    session_id TEXT,
    state TEXT,
    context TEXT,
    step_number INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_id) REFERENCES state_sessions(session_id)
);

CREATE INDEX IF NOT EXISTS idx_transitions_session ON state_transitions(session_id);
CREATE INDEX IF NOT EXISTS idx_checkpoints_session ON state_checkpoints(session_id);
EOF
    
    echo "✅ 状态机已初始化"
}

# 创建新会话
create_session() {
    local session_id="${1:-$(uuidgen 2>/dev/null || echo "session-$(date +%s)-$$-$RANDOM")}"
    local context="${2:-{}}"
    
    sqlite3 "$STATE_DB" << EOF
INSERT INTO state_sessions (session_id, current_state, context)
VALUES ('$session_id', 'IDLE', '$(echo "$context" | sed "s/'/''/g")');
EOF
    
    echo "$session_id"
}

# 获取当前状态
get_current_state() {
    local session_id="$1"
    
    sqlite3 "$STATE_DB" << EOF
SELECT current_state FROM state_sessions WHERE session_id = '$session_id';
EOF
}

# 检查状态转换是否允许
is_transition_allowed() {
    local from_state="$1"
    local to_state="$2"
    
    # 从配置文件读取允许的状态转换
    local allowed=$(jq -r --arg from "$from_state" --arg to "$to_state" '
        .states[$from].allowed_transitions | contains([$to])
    ' ~/.openclaw/agent_loop/state_machine_config.json 2>/dev/null)
    
    if [ "$allowed" = "true" ]; then
        return 0
    else
        return 1
    fi
}

# 执行状态转换
transition() {
    local session_id="$1"
    local new_state="$2"
    local transition_name="${3:-manual}"
    local metadata="${4:-{}}"
    
    local current_state=$(get_current_state "$session_id")
    
    echo "[State Machine] $current_state → $new_state ($transition_name)"
    
    # 检查转换是否允许
    if ! is_transition_allowed "$current_state" "$new_state"; then
        echo -e "${RED}❌ 状态转换不允许: $current_state → $new_state${NC}"
        return 1
    fi
    
    # 执行 on_exit 钩子
    execute_hook "$current_state" "on_exit" "$session_id"
    
    # 更新状态
    sqlite3 "$STATE_DB" << EOF
UPDATE state_sessions 
SET current_state = '$new_state',
    previous_state = '$current_state',
    updated_at = CURRENT_TIMESTAMP,
    metadata = json_patch(metadata, '$(echo "$metadata" | sed "s/'/''/g")')
WHERE session_id = '$session_id';

INSERT INTO state_transitions (session_id, from_state, to_state, transition_name, metadata)
VALUES ('$session_id', '$current_state', '$new_state', '$transition_name', '$(echo "$metadata" | sed "s/'/''/g")');
EOF
    
    # 执行 on_enter 钩子
    execute_hook "$new_state" "on_enter" "$session_id"
    
    # 如果是终态，清理资源
    if is_final_state "$new_state"; then
        cleanup_session "$session_id"
    fi
    
    echo -e "${GREEN}✅ 状态转换成功: $new_state${NC}"
    return 0
}

# 执行状态钩子
execute_hook() {
    local state="$1"
    local hook="$2"
    local session_id="$3"
    
    local hook_action=$(jq -r --arg state "$state" --arg hook "$hook" '
        .states[$state][$hook] // empty
    ' ~/.openclaw/agent_loop/state_machine_config.json 2>/dev/null)
    
    case "$hook_action" in
        "clear_context")
            echo "[Hook] 清除上下文"
            ;;
        "prepare_session")
            echo "[Hook] 准备会话"
            ;;
        "validate_request")
            echo "[Hook] 验证请求"
            ;;
        "start_execution")
            echo "[Hook] 开始执行"
            ;;
        "save_checkpoint")
            save_checkpoint "$session_id"
            ;;
        "notify_user")
            echo "[Hook] 通知用户"
            ;;
        "save_state")
            save_checkpoint "$session_id"
            ;;
        "restore_state")
            restore_from_checkpoint "$session_id"
            ;;
        "cleanup_session")
            echo "[Hook] 清理会话"
            ;;
        "log_error")
            log_error "$session_id"
            ;;
        "increment_retry")
            increment_retry "$session_id"
            ;;
    esac
}

# 保存检查点 (Checkpoint)
save_checkpoint() {
    local session_id="$1"
    local checkpoint_id="${2:-checkpoint-$(date +%s)}"
    
    local state=$(get_current_state "$session_id")
    local context=$(sqlite3 "$STATE_DB" "SELECT context FROM state_sessions WHERE session_id = '$session_id';")
    local step_number=$(sqlite3 "$STATE_DB" "SELECT COUNT(*) FROM state_transitions WHERE session_id = '$session_id';")
    
    sqlite3 "$STATE_DB" << EOF
INSERT INTO state_checkpoints (checkpoint_id, session_id, state, context, step_number)
VALUES ('$checkpoint_id', '$session_id', '$state', '$context', $step_number);
EOF
    
    echo "[Checkpoint] 已保存: $checkpoint_id ($state, step $step_number)"
}

# 从检查点恢复
restore_from_checkpoint() {
    local session_id="$1"
    local checkpoint_id="$2"
    
    if [ -z "$checkpoint_id" ]; then
        # 获取最新的检查点
        checkpoint_id=$(sqlite3 "$STATE_DB" << EOF
SELECT checkpoint_id FROM state_checkpoints 
WHERE session_id = '$session_id' 
ORDER BY created_at DESC LIMIT 1;
EOF
)
    fi
    
    if [ -z "$checkpoint_id" ]; then
        echo -e "${RED}❌ 没有找到检查点${NC}"
        return 1
    fi
    
    local checkpoint=$(sqlite3 "$STATE_DB" << EOF
SELECT state, context, step_number FROM state_checkpoints 
WHERE checkpoint_id = '$checkpoint_id';
EOF
)
    
    local state=$(echo "$checkpoint" | cut -d'|' -f1)
    local context=$(echo "$checkpoint" | cut -d'|' -f2)
    local step=$(echo "$checkpoint" | cut -d'|' -f3)
    
    sqlite3 "$STATE_DB" << EOF
UPDATE state_sessions 
SET current_state = '$state', context = '$context'
WHERE session_id = '$session_id';
EOF
    
    echo "[Checkpoint] 已恢复: $checkpoint_id → $state (step $step)"
}

# 列出所有检查点
list_checkpoints() {
    local session_id="$1"
    
    echo "=== 检查点列表 (Session: $session_id) ==="
    sqlite3 "$STATE_DB" << EOF
SELECT checkpoint_id, state, step_number, strftime('%Y-%m-%d %H:%M', created_at) as time
FROM state_checkpoints 
WHERE session_id = '$session_id'
ORDER BY created_at DESC;
EOF
}

# 暂停会话
pause_session() {
    local session_id="$1"
    transition "$session_id" "PAUSED" "pause"
}

# 恢复会话
resume_session() {
    local session_id="$1"
    local from_state=$(get_current_state "$session_id")
    
    if [ "$from_state" = "PAUSED" ]; then
        transition "$session_id" "RUNNING" "unpause"
    elif [ "$from_state" = "WAITING" ]; then
        transition "$session_id" "RUNNING" "resume"
    else
        echo -e "${YELLOW}⚠️ 会话不在可恢复状态: $from_state${NC}"
        return 1
    fi
}

# 取消会话
cancel_session() {
    local session_id="$1"
    transition "$session_id" "CANCELLED" "cancel"
}

# 检查是否是终态
is_final_state() {
    local state="$1"
    local is_final=$(jq -r --arg state "$state" '
        .states[$state].final // false
    ' ~/.openclaw/agent_loop/state_machine_config.json 2>/dev/null)
    
    [ "$is_final" = "true" ]
}

# 获取会话统计
get_session_stats() {
    local session_id="$1"
    
    echo "=== 会话统计 (Session: $session_id) ==="
    
    echo "当前状态:"
    sqlite3 "$STATE_DB" << EOF
SELECT current_state, retry_count, 
       strftime('%Y-%m-%d %H:%M:%S', created_at) as created,
       strftime('%Y-%m-%d %H:%M:%S', updated_at) as updated
FROM state_sessions WHERE session_id = '$session_id';
EOF
    
    echo ""
    echo "状态转换历史:"
    sqlite3 "$STATE_DB" << EOF
SELECT from_state, to_state, transition_name, 
       strftime('%H:%M:%S', timestamp) as time
FROM state_transitions 
WHERE session_id = '$session_id'
ORDER BY timestamp;
EOF
}

# 列出所有会话
list_sessions() {
    echo "=== 所有会话 ==="
    sqlite3 "$STATE_DB" << EOF
SELECT session_id, current_state, retry_count,
       strftime('%Y-%m-%d %H:%M', updated_at) as last_update
FROM state_sessions
ORDER BY updated_at DESC
LIMIT 20;
EOF
}

# 记录错误
log_error() {
    local session_id="$1"
    echo "[Error] 会话 $session_id 发生错误"
}

# 增加重试计数
increment_retry() {
    local session_id="$1"
    
    sqlite3 "$STATE_DB" << EOF
UPDATE state_sessions 
SET retry_count = retry_count + 1
WHERE session_id = '$session_id';
EOF
    
    local count=$(sqlite3 "$STATE_DB" "SELECT retry_count FROM state_sessions WHERE session_id = '$session_id';")
    echo "[Retry] 重试次数: $count"
}

# 清理会话
cleanup_session() {
    local session_id="$1"
    echo "[Cleanup] 清理会话资源: $session_id"
    # 保留历史记录，只清理临时资源
}

# 测试状态机
test_state_machine() {
    echo "=== 测试 Agent 状态机 ==="
    echo ""
    
    # 创建会话
    local session=$(create_session "" '{"task": "测试任务"}')
    echo "创建会话: $session"
    
    # 测试状态转换
    echo ""
    echo "1. IDLE → PENDING"
    transition "$session" "PENDING" "start"
    
    echo ""
    echo "2. PENDING → RUNNING"
    transition "$session" "RUNNING" "execute"
    
    echo ""
    echo "3. 保存检查点"
    save_checkpoint "$session" "test-checkpoint-1"
    
    echo ""
    echo "4. RUNNING → WAITING"
    transition "$session" "WAITING" "wait"
    
    echo ""
    echo "5. WAITING → RUNNING (恢复)"
    resume_session "$session"
    
    echo ""
    echo "6. RUNNING → COMPLETED"
    transition "$session" "COMPLETED" "complete"
    
    echo ""
    echo "=== 会话统计 ==="
    get_session_stats "$session"
}

# 主入口
main() {
    case "$1" in
        "init")
            init_state_machine
            ;;
        "create")
            create_session "$2" "$3"
            ;;
        "transition"|"t")
            transition "$2" "$3" "$4" "$5"
            ;;
        "state"|"s")
            get_current_state "$2"
            ;;
        "pause")
            pause_session "$2"
            ;;
        "resume")
            resume_session "$2"
            ;;
        "cancel")
            cancel_session "$2"
            ;;
        "checkpoint"|"cp")
            save_checkpoint "$2" "$3"
            ;;
        "restore")
            restore_from_checkpoint "$2" "$3"
            ;;
        "list-checkpoints"|"lc")
            list_checkpoints "$2"
            ;;
        "stats")
            get_session_stats "$2"
            ;;
        "list"|"ls")
            list_sessions
            ;;
        "test")
            test_state_machine
            ;;
        *)
            echo "Agent State Machine - 基于 Claude Code 架构"
            echo ""
            echo "用法:"
            echo "  $0 init                           - 初始化状态机"
            echo "  $0 create [session_id] [context]  - 创建会话"
            echo "  $0 transition <session> <state> [name] [meta] - 状态转换"
            echo "  $0 state <session>                - 获取当前状态"
            echo "  $0 pause <session>                - 暂停会话"
            echo "  $0 resume <session>               - 恢复会话"
            echo "  $0 cancel <session>               - 取消会话"
            echo "  $0 checkpoint <session> [id]      - 保存检查点"
            echo "  $0 restore <session> [id]         - 从检查点恢复"
            echo "  $0 list-checkpoints <session>     - 列出检查点"
            echo "  $0 stats <session>                - 会话统计"
            echo "  $0 list                           - 列出所有会话"
            echo "  $0 test                           - 测试状态机"
            ;;
    esac
}

main "$@"
