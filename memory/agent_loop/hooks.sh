#!/bin/bash
# hooks.sh - OpenClaw Agent Event Hooks System
# 基于 Claude Code 架构，支持 20+ 钩子点

HOOKS_DIR="/root/.openclaw/agent_loop/hooks"
HOOKS_DB="$HOOKS_DIR/hooks.db"
HOOKS_LOG="$HOOKS_DIR/hooks.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 初始化钩子系统
init_hooks_system() {
    mkdir -p "$HOOKS_DIR"/{registry,handlers,logs}
    
    # 创建 SQLite 数据库
    sqlite3 "$HOOKS_DB" << 'EOF'
CREATE TABLE IF NOT EXISTS hook_registry (
    hook_id TEXT PRIMARY KEY,
    event_name TEXT NOT NULL,
    handler_path TEXT NOT NULL,
    priority INTEGER DEFAULT 50,
    enabled INTEGER DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    description TEXT
);

CREATE TABLE IF NOT EXISTS hook_executions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_name TEXT,
    hook_id TEXT,
    session_id TEXT,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    duration_ms INTEGER,
    success INTEGER,
    error_message TEXT,
    cancelled INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS event_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_name TEXT,
    session_id TEXT,
    triggered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    hooks_count INTEGER,
    total_duration_ms INTEGER
);

CREATE INDEX IF NOT EXISTS idx_hooks_event ON hook_registry(event_name);
CREATE INDEX IF NOT EXISTS idx_hooks_enabled ON hook_registry(enabled);
CREATE INDEX IF NOT EXISTS idx_executions_event ON hook_executions(event_name);
CREATE INDEX IF NOT EXISTS idx_executions_session ON hook_executions(session_id);
EOF
    
    # 创建默认钩子处理器目录
    mkdir -p "$HOOKS_DIR/handlers"/{logging,metrics,security,notifications}
    
    # 创建默认日志钩子
    create_default_logging_hooks
    
    echo "✅ 事件钩子系统已初始化"
}

# 创建默认日志钩子
create_default_logging_hooks() {
    # before_tool_call 日志钩子
    cat > "$HOOKS_DIR/handlers/logging/before_tool_call.sh" << 'EOF'
#!/bin/bash
# 默认日志钩子: before_tool_call
EVENT="$1"
SESSION_ID="$2"
TOOL_NAME="$3"
ARGS="$4"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$EVENT] Session: $SESSION_ID, Tool: $TOOL_NAME" >> ~/.openclaw/agent_loop/hooks/logs/tool_calls.log
EOF
    chmod +x "$HOOKS_DIR/handlers/logging/before_tool_call.sh"
    
    # on_error 日志钩子
    cat > "$HOOKS_DIR/handlers/logging/on_error.sh" << 'EOF'
#!/bin/bash
# 默认日志钩子: on_error
EVENT="$1"
SESSION_ID="$2"
ERROR_TYPE="$3"
ERROR_MSG="$4"
CONTEXT="$5"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] Session: $SESSION_ID, Type: $ERROR_TYPE, Msg: $ERROR_MSG" >> ~/.openclaw/agent_loop/hooks/logs/errors.log
EOF
    chmod +x "$HOOKS_DIR/handlers/logging/on_error.sh"
    
    # 注册默认钩子
    register_hook "before_tool_call" "$HOOKS_DIR/handlers/logging/before_tool_call.sh" 100 "Default logging hook"
    register_hook "on_error" "$HOOKS_DIR/handlers/logging/on_error.sh" 100 "Default error logging hook"
}

# 注册钩子
register_hook() {
    local event_name="$1"
    local handler_path="$2"
    local priority="${3:-50}"
    local description="${4:-}"
    local hook_id="hook-$(date +%s)-$RANDOM"
    
    # 验证事件名称
    if ! is_valid_event "$event_name"; then
        echo -e "${RED}❌ 无效的事件名称: $event_name${NC}"
        return 1
    fi
    
    # 验证处理器文件存在
    if [ ! -f "$handler_path" ]; then
        echo -e "${RED}❌ 处理器文件不存在: $handler_path${NC}"
        return 1
    fi
    
    # 注册到数据库
    sqlite3 "$HOOKS_DB" << EOF
INSERT INTO hook_registry (hook_id, event_name, handler_path, priority, description)
VALUES ('$hook_id', '$event_name', '$handler_path', $priority, '$(echo "$description" | sed "s/'/''/g")');
EOF
    
    echo -e "${GREEN}✅ 钩子已注册: $hook_id${NC}"
    echo "   事件: $event_name"
    echo "   处理器: $handler_path"
    echo "   优先级: $priority"
}

# 注销钩子
unregister_hook() {
    local hook_id="$1"
    
    sqlite3 "$HOOKS_DB" << EOF
DELETE FROM hook_registry WHERE hook_id = '$hook_id';
EOF
    
    echo -e "${GREEN}✅ 钩子已注销: $hook_id${NC}"
}

# 启用/禁用钩子
enable_hook() {
    local hook_id="$1"
    local enabled="${2:-1}"
    
    sqlite3 "$HOOKS_DB" << EOF
UPDATE hook_registry SET enabled = $enabled WHERE hook_id = '$hook_id';
EOF
    
    if [ "$enabled" -eq 1 ]; then
        echo -e "${GREEN}✅ 钩子已启用: $hook_id${NC}"
    else
        echo -e "${YELLOW}⏸️ 钩子已禁用: $hook_id${NC}"
    fi
}

# 触发事件
trig_event() {
    local event_name="$1"
    shift
    local args=("$@")
    
    # 验证事件名称
    if ! is_valid_event "$event_name"; then
        echo "[Hooks] 警告: 未定义的事件 '$event_name'" >&2
        return 0
    fi
    
    # 记录事件触发
    local session_id="${args[0]:-unknown}"
    local start_time=$(date +%s%3N)
    
    # 获取该事件的所有启用的钩子
    local hooks=$(sqlite3 "$HOOKS_DB" << EOF
SELECT hook_id, handler_path FROM hook_registry 
WHERE event_name = '$event_name' AND enabled = 1 
ORDER BY priority DESC;
EOF
)
    
    local hooks_count=0
    local total_duration=0
    
    # 执行每个钩子
    while IFS='|' read -r hook_id handler_path; do
        [ -z "$hook_id" ] && continue
        
        hooks_count=$((hooks_count + 1))
        local hook_start=$(date +%s%3N)
        
        # 执行钩子处理器
        if [ -x "$handler_path" ]; then
            local result
            result=$("$handler_path" "$event_name" "${args[@]}" 2>&1)
            local exit_code=$?
            
            local hook_end=$(date +%s%3N)
            local duration=$((hook_end - hook_start))
            total_duration=$((total_duration + duration))
            
            # 记录执行结果
            local success=0
            local error_msg=""
            local cancelled=0
            
            if [ $exit_code -eq 0 ]; then
                success=1
            elif [ $exit_code -eq 99 ]; then
                # 钩子请求取消操作
                cancelled=1
                success=1
                echo "[Hooks] 钩子 $hook_id 请求取消操作"
            else
                error_msg="$(echo "$result" | head -1 | sed "s/'/''/g")"
            fi
            
            sqlite3 "$HOOKS_DB" << EOF
INSERT INTO hook_executions (event_name, hook_id, session_id, duration_ms, success, error_message, cancelled)
VALUES ('$event_name', '$hook_id', '$session_id', $duration, $success, '$error_msg', $cancelled);
EOF
            
            # 如果钩子请求取消，返回取消信号
            if [ $cancelled -eq 1 ]; then
                return 99
            fi
        fi
    done <<< "$hooks"
    
    # 记录事件历史
    sqlite3 "$HOOKS_DB" << EOF
INSERT INTO event_history (event_name, session_id, hooks_count, total_duration_ms)
VALUES ('$event_name', '$session_id', $hooks_count, $total_duration);
EOF
    
    return 0
}

# 验证事件名称是否有效
is_valid_event() {
    local event_name="$1"
    
    jq -e --arg event "$event_name" '.hooks[$event]' ~/.openclaw/agent_loop/hooks_config.json > /dev/null 2>&1
}

# 获取事件信息
get_event_info() {
    local event_name="$1"
    
    if ! is_valid_event "$event_name"; then
        echo "无效的事件: $event_name"
        return 1
    fi
    
    echo "=== 事件信息: $event_name ==="
    jq --arg event "$event_name" '.hooks[$event]' ~/.openclaw/agent_loop/hooks_config.json
    
    echo ""
    echo "已注册的钩子:"
    sqlite3 "$HOOKS_DB" << EOF
SELECT hook_id, priority, enabled, description 
FROM hook_registry 
WHERE event_name = '$event_name'
ORDER BY priority DESC;
EOF
}

# 列出所有事件
list_events() {
    echo "=== 可用事件钩子 ==="
    jq -r '.hooks | keys[] as $k | "  - \($k): \(.[$k].description)"' ~/.openclaw/agent_loop/hooks_config.json
}

# 列出已注册的钩子
list_hooks() {
    local event_filter="${1:-}"
    
    echo "=== 已注册的钩子 ==="
    
    if [ -n "$event_filter" ]; then
        sqlite3 "$HOOKS_DB" << EOF
SELECT hook_id, event_name, priority, enabled, description 
FROM hook_registry 
WHERE event_name = '$event_filter'
ORDER BY event_name, priority DESC;
EOF
    else
        sqlite3 "$HOOKS_DB" << EOF
SELECT hook_id, event_name, priority, enabled, description 
FROM hook_registry 
ORDER BY event_name, priority DESC
LIMIT 20;
EOF
    fi
}

# 获取钩子统计
get_hooks_stats() {
    echo "=== 钩子执行统计 ==="
    
    echo ""
    echo "最活跃的事件:"
    sqlite3 "$HOOKS_DB" << EOF
SELECT event_name, COUNT(*) as count 
FROM event_history 
GROUP BY event_name 
ORDER BY count DESC 
LIMIT 5;
EOF
    
    echo ""
    echo "执行时间最长的钩子:"
    sqlite3 "$HOOKS_DB" << EOF
SELECT hook_id, AVG(duration_ms) as avg_duration, COUNT(*) as count
FROM hook_executions 
GROUP BY hook_id 
ORDER BY avg_duration DESC 
LIMIT 5;
EOF
    
    echo ""
    echo "错误率最高的钩子:"
    sqlite3 "$HOOKS_DB" << EOF
SELECT hook_id, 
       SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as error_rate,
       COUNT(*) as total
FROM hook_executions 
GROUP BY hook_id 
HAVING COUNT(*) > 5
ORDER BY error_rate DESC 
LIMIT 5;
EOF
}

# 创建示例钩子处理器
create_example_hook() {
    local event_name="$1"
    local hook_name="${2:-custom}"
    
    local handler_path="$HOOKS_DIR/handlers/${hook_name}_${event_name}.sh"
    
    cat > "$handler_path" << EOF
#!/bin/bash
# 自定义钩子: $hook_name
# 事件: $event_name

EVENT="\$1"
shift

# 事件参数
$(jq -r --arg event "$event_name" '.hooks[$event].arguments | map("\(.)=\"\$1\"\nshift") | join("\n")' ~/.openclaw/agent_loop/hooks_config.json 2>/dev/null || echo "# 参数: \$@")

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$EVENT] 自定义钩子执行" >> ~/.openclaw/agent_loop/hooks/logs/custom.log

# 如果要取消操作，返回 exit code 99
# exit 99

exit 0
EOF
    chmod +x "$handler_path"
    
    echo -e "${GREEN}✅ 示例钩子已创建: $handler_path${NC}"
    echo "编辑后使用以下命令注册:"
    echo "  hooks.sh register $event_name $handler_path 50 '描述'"
}

# 测试钩子系统
test_hooks_system() {
    echo "=== 测试事件钩子系统 ==="
    echo ""
    
    # 测试 1: 触发简单事件
    echo "测试 1: 触发 before_tool_call 事件"
    trig_event "before_tool_call" "test-session-123" "tavily-search" '{"query": "test"}'
    
    echo ""
    echo "测试 2: 触发 on_error 事件"
    trig_event "on_error" "test-session-123" "TEST_ERROR" "Test error message" "{}"
    
    echo ""
    echo "测试 3: 查看执行日志"
    tail -5 ~/.openclaw/agent_loop/hooks/logs/tool_calls.log 2>/dev/null || echo "暂无日志"
    
    echo ""
    echo "测试完成！"
}

# 主入口
main() {
    case "$1" in
        "init")
            init_hooks_system
            ;;
        "register")
            register_hook "$2" "$3" "$4" "$5"
            ;;
        "unregister")
            unregister_hook "$2"
            ;;
        "enable"|"disable")
            enable_hook "$2" "$([ "$1" = "enable" ] && echo 1 || echo 0)"
            ;;
        "trigger"|"trig")
            trig_event "$2" "${@:3}"
            ;;
        "event")
            get_event_info "$2"
            ;;
        "events")
            list_events
            ;;
        "list")
            list_hooks "$2"
            ;;
        "stats")
            get_hooks_stats
            ;;
        "create-example")
            create_example_hook "$2" "$3"
            ;;
        "test")
            test_hooks_system
            ;;
        *)
            echo "Agent Event Hooks System - 基于 Claude Code 架构"
            echo ""
            echo "用法:"
            echo "  $0 init                           - 初始化钩子系统"
            echo "  $0 register <event> <handler> [priority] [desc] - 注册钩子"
            echo "  $0 unregister <hook_id>           - 注销钩子"
            echo "  $0 enable|disable <hook_id>       - 启用/禁用钩子"
            echo "  $0 trigger <event> [args...]      - 触发事件"
            echo "  $0 event <event_name>             - 查看事件信息"
            echo "  $0 events                         - 列出所有事件"
            echo "  $0 list [event_filter]            - 列出已注册钩子"
            echo "  $0 stats                          - 钩子统计"
            echo "  $0 create-example <event> [name]  - 创建示例钩子"
            echo "  $0 test                           - 测试钩子系统"
            ;;
    esac
}

main "$@"
