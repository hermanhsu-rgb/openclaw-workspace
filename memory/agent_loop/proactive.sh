#!/bin/bash
# proactive.sh - OpenClaw Proactive Mode
# 基于 Claude Code 架构：主动预测用户需求、智能建议

PROACTIVE_DIR="/root/.openclaw/agent_loop/proactive"
CONFIG_FILE="/root/.openclaw/agent_loop/proactive_config.json"
SUGGESTIONS_DB="$PROACTIVE_DIR/suggestions.db"
USER_BEHAVIOR_DB="$PROACTIVE_DIR/behavior.db"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 初始化 Proactive Mode
init_proactive() {
    echo "初始化 Proactive Mode..."
    mkdir -p "$PROACTIVE_DIR"/{suggestions,behavior,learned}
    
    # 创建建议数据库
    sqlite3 "$SUGGESTIONS_DB" << 'EOF'
CREATE TABLE IF NOT EXISTS suggestions (
    suggestion_id TEXT PRIMARY KEY,
    trigger_type TEXT,
    trigger_context TEXT,
    suggestion_text TEXT,
    confidence REAL,
    priority TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    shown_at TIMESTAMP,
    user_response TEXT,
    accepted INTEGER,
    dismissed INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS proactive_stats (
    date TEXT PRIMARY KEY,
    suggestions_generated INTEGER DEFAULT 0,
    suggestions_shown INTEGER DEFAULT 0,
    suggestions_accepted INTEGER DEFAULT 0,
    suggestions_dismissed INTEGER DEFAULT 0
);
EOF
    
    # 创建用户行为数据库
    sqlite3 "$USER_BEHAVIOR_DB" << 'EOF'
CREATE TABLE IF NOT EXISTS user_actions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    action_type TEXT,
    action_detail TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    session_id TEXT,
    context TEXT
);

CREATE TABLE IF NOT EXISTS action_patterns (
    pattern_id TEXT PRIMARY KEY,
    pattern_type TEXT,
    pattern_signature TEXT,
    frequency INTEGER DEFAULT 1,
    last_seen TIMESTAMP,
    suggested_automation INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS learned_preferences (
    preference_key TEXT PRIMARY KEY,
    preference_value TEXT,
    confidence REAL,
    learned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_actions_time ON user_actions(timestamp);
CREATE INDEX IF NOT EXISTS idx_actions_type ON user_actions(action_type);
EOF
    
    echo "✅ Proactive Mode 已初始化"
}

# 记录用户行为
record_action() {
    local action_type="$1"
    local action_detail="$2"
    local context="${3:-}"
    local session_id="${4:-default}"
    
    sqlite3 "$USER_BEHAVIOR_DB" << EOF
INSERT INTO user_actions (action_type, action_detail, session_id, context)
VALUES ('$action_type', '$(echo "$action_detail" | sed "s/'/''/g")', '$session_id', '$(echo "$context" | sed "s/'/''/g")');
EOF
    
    # 分析是否有模式
    analyze_patterns "$action_type" "$action_detail"
}

# 分析行为模式
analyze_patterns() {
    local action_type="$1"
    local action_detail="$2"
    
    # 检查重复操作
    local recent_count=$(sqlite3 "$USER_BEHAVIOR_DB" << EOF
SELECT COUNT(*) FROM user_actions 
WHERE action_type = '$action_type' 
AND action_detail = '$(echo "$action_detail" | sed "s/'/''/g")'
AND timestamp > datetime('now', '-10 minutes');
EOF
)
    
    if [ "$recent_count" -ge 3 ]; then
        # 检测到重复模式
        local pattern_sig="${action_type}:${action_detail}"
        
        sqlite3 "$USER_BEHAVIOR_DB" << EOF
INSERT INTO action_patterns (pattern_id, pattern_type, pattern_signature, last_seen)
VALUES ('pattern-$(date +%s)', 'repetitive', '$(echo "$pattern_sig" | sed "s/'/''/g")', CURRENT_TIMESTAMP)
ON CONFLICT(pattern_id) DO UPDATE SET 
    frequency = frequency + 1,
    last_seen = CURRENT_TIMESTAMP;
EOF
        
        # 生成建议
        if [ "$recent_count" -eq 3 ]; then
            generate_suggestion "user_behavior" "repetitive_action" "检测到重复操作 '$action_detail'，建议创建自动化脚本" 0.8 "medium"
        fi
    fi
}

# 生成建议
generate_suggestion() {
    local trigger_type="$1"
    local trigger_context="$2"
    local suggestion_text="$3"
    local confidence="${4:-0.7}"
    local priority="${5:-medium}"
    local suggestion_id="sugg-$(date +%s)-$RANDOM"
    
    # 检查冷却时间
    local recent_suggestions=$(sqlite3 "$SUGGESTIONS_DB" << EOF
SELECT COUNT(*) FROM suggestions 
WHERE created_at > datetime('now', '-1 hour');
EOF
)
    
    local max_per_hour=$(jq -r '.suggestion_engine.max_suggestions_per_hour // 5' "$CONFIG_FILE")
    if [ "$recent_suggestions" -ge "$max_per_hour" ]; then
        return 1
    fi
    
    # 保存建议
    sqlite3 "$SUGGESTIONS_DB" << EOF
INSERT INTO suggestions (suggestion_id, trigger_type, trigger_context, suggestion_text, confidence, priority)
VALUES ('$suggestion_id', '$trigger_type', '$(echo "$trigger_context" | sed "s/'/''/g")', '$(echo "$suggestion_text" | sed "s/'/''/g")', $confidence, '$priority');
EOF
    
    # 显示建议
    show_suggestion "$suggestion_id" "$suggestion_text" "$priority"
    
    return 0
}

# 显示建议
show_suggestion() {
    local suggestion_id="$1"
    local text="$2"
    local priority="$3"
    
    echo ""
    case "$priority" in
        "high")
            echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
            echo -e "${RED}║  🤖 Proactive Agent - 重要提醒                        ║${NC}"
            echo -e "${RED}╚════════════════════════════════════════════════════════╝${NC}"
            ;;
        "medium")
            echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
            echo -e "${CYAN}║  🤖 Proactive Agent - 智能建议                      ║${NC}"
            echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
            ;;
        *)
            echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
            echo -e "${BLUE}║  🤖 Proactive Agent                                  ║${NC}"
            echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
            ;;
    esac
    
    echo ""
    echo "💡 $text"
    echo ""
    echo "选项:"
    echo "  [Y] 接受建议并执行"
    echo "  [N] 忽略此建议"
    echo "  [?] 查看详情"
    echo ""
    
    # 更新显示时间
    sqlite3 "$SUGGESTIONS_DB" "UPDATE suggestions SET shown_at = CURRENT_TIMESTAMP WHERE suggestion_id = '$suggestion_id';"
    
    # 记录今日统计
    local today=$(date +%Y-%m-%d)
    sqlite3 "$SUGGESTIONS_DB" << EOF
INSERT INTO proactive_stats (date, suggestions_shown)
VALUES ('$today', 1)
ON CONFLICT(date) DO UPDATE SET suggestions_shown = suggestions_shown + 1;
EOF
}

# 检查文件变化并建议
check_file_changes() {
    local watch_dir="${1:-~/.openclaw/workspace}"
    
    # 查找最近修改的文件
    local recent_files=$(find "$watch_dir" -type f -mtime -0.01 2>/dev/null | grep -E '\.(js|ts|py|sh|md|json)$' | head -5)
    
    if [ -n "$recent_files" ]; then
        # 检查代码模式
        while IFS= read -r file; do
            [ -f "$file" ] || continue
            
            # 检查 TODO 注释
            if grep -qE 'TODO|FIXME|XXX' "$file" 2>/dev/null; then
                generate_suggestion "file_change" "todo_found" "在 $(basename "$file") 中发现 TODO 注释，是否创建任务跟踪？" 0.75 "medium"
                break
            fi
            
            # 检查硬编码敏感信息
            if grep -qE "(password|secret|key|token)\s*=\s*['\"][^'\"]+['\"]" "$file" 2>/dev/null; then
                generate_suggestion "file_change" "hardcoded_secret" "在 $(basename "$file") 中发现硬编码敏感信息，建议使用环境变量" 0.9 "high"
                break
            fi
            
            # 检查调试日志
            if grep -qE "console\.(log|warn|error)" "$file" 2>/dev/null; then
                generate_suggestion "file_change" "debug_log" "在 $(basename "$file") 中发现调试日志，生产环境建议移除" 0.6 "low"
                break
            fi
        done <<< "$recent_files"
    fi
}

# 基于时间检查
 check_time_based_suggestions() {
    local current_hour=$(date +%H)
    local current_day=$(date +%u)  # 1-5 是工作日
    
    # 早上检查
    if [ "$current_hour" = "09" ] && [ "$current_day" -le 5 ]; then
        # 检查今天是否已建议
        local today=$(date +%Y-%m-%d)
        local already_suggested=$(sqlite3 "$SUGGESTIONS_DB" "SELECT COUNT(*) FROM suggestions WHERE trigger_type = 'time_based' AND date(created_at) = '$today';")
        
        if [ "$already_suggested" -eq 0 ]; then
            generate_suggestion "time_based" "morning_greeting" "早上好！今日任务：1)检查系统状态 2)查看skills更新 3)备份工作" 0.7 "medium"
        fi
    fi
    
    # 下班检查
    if [ "$current_hour" = "18" ] && [ "$current_day" -le 5 ]; then
        generate_suggestion "time_based" "evening_backup" "下班时间到了，需要备份今日工作到GitHub吗？" 0.8 "medium"
    fi
}

# 检查系统状态
 check_system_state() {
    # 磁盘检查
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    if [ "$disk_usage" -ge 85 ]; then
        generate_suggestion "system_state" "disk_full" "磁盘使用率已达 ${disk_usage}%，建议清理日志文件" 0.9 "high"
    fi
    
    # 内存检查
    local memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    if [ "$memory_usage" -ge 80 ]; then
        generate_suggestion "system_state" "memory_high" "内存使用率已达 ${memory_usage}%，建议重启服务" 0.85 "high"
    fi
}

# 处理用户响应
 handle_response() {
    local suggestion_id="$1"
    local response="$2"
    
    sqlite3 "$SUGGESTIONS_DB" "UPDATE suggestions SET user_response = '$response' WHERE suggestion_id = '$suggestion_id';"
    
    case "$response" in
        "Y"|"y"|"yes")
            sqlite3 "$SUGGESTIONS_DB" "UPDATE suggestions SET accepted = 1 WHERE suggestion_id = '$suggestion_id';"
            
            local today=$(date +%Y-%m-%d)
            sqlite3 "$SUGGESTIONS_DB" "INSERT INTO proactive_stats (date, suggestions_accepted) VALUES ('$today', 1) ON CONFLICT(date) DO UPDATE SET suggestions_accepted = suggestions_accepted + 1;"
            
            echo -e "${GREEN}✅ 建议已接受，正在执行...${NC}"
            return 0
            ;;
        "N"|"n"|"no")
            sqlite3 "$SUGGESTIONS_DB" "UPDATE suggestions SET dismissed = 1 WHERE suggestion_id = '$suggestion_id';"
            
            local today=$(date +%Y-%m-%d)
            sqlite3 "$SUGGESTIONS_DB" "INSERT INTO proactive_stats (date, suggestions_dismissed) VALUES ('$today', 1) ON CONFLICT(date) DO UPDATE SET suggestions_dismissed = suggestions_dismissed + 1;"
            
            echo "建议已忽略"
            return 1
            ;;
        *)
            echo "显示详情..."
            return 1
            ;;
    esac
}

# 运行 Proactive 检查循环
 proactive_loop() {
    echo "🤖 Proactive Mode 运行中..."
    echo "按 Ctrl+C 停止"
    echo ""
    
    while true; do
        # 每 5 分钟检查一次
        check_file_changes
        check_time_based_suggestions
        check_system_state
        
        sleep 300
    done
}

# 显示统计
 show_stats() {
    echo "=== Proactive Mode 统计 ==="
    echo ""
    
    echo "最近7天建议统计:"
    sqlite3 "$SUGGESTIONS_DB" << EOF
SELECT 
    date,
    suggestions_shown as shown,
    suggestions_accepted as accepted,
    suggestions_dismissed as dismissed,
    ROUND(suggestions_accepted * 100.0 / (suggestions_shown + 0.01), 1) as accept_rate
FROM proactive_stats
WHERE date >= date('now', '-7 days')
ORDER BY date DESC;
EOF
    
    echo ""
    echo "用户行为模式:"
    sqlite3 "$USER_BEHAVIOR_DB" << EOF
SELECT pattern_type, pattern_signature, frequency, last_seen
FROM action_patterns
ORDER BY frequency DESC
LIMIT 10;
EOF
}

# 测试 Proactive Mode
 test_proactive() {
    echo "=== 测试 Proactive Mode ==="
    echo ""
    
    echo "测试 1: 记录用户行为"
    record_action "command" "git status" "terminal"
    record_action "command" "git status" "terminal"
    record_action "command" "git status" "terminal"
    
    echo ""
    echo "测试 2: 生成建议"
    generate_suggestion "test" "manual" "这是一个测试建议：检测到您经常使用 git status，建议创建一个别名 'gs'" 0.8 "medium"
    
    echo ""
    echo "测试 3: 检查文件变化"
    check_file_changes ~/.openclaw/agent_loop
    
    echo ""
    echo "测试完成！"
}

# 主入口
 main() {
    case "$1" in
        "init")
            init_proactive
            ;;
        "record")
            record_action "$2" "$3" "$4" "$5"
            ;;
        "suggest")
            generate_suggestion "$2" "$3" "$4" "$5" "$6"
            ;;
        "respond")
            handle_response "$2" "$3"
            ;;
        "loop")
            proactive_loop
            ;;
        "check")
            check_file_changes "$2"
            check_system_state
            ;;
        "stats")
            show_stats
            ;;
        "test")
            test_proactive
            ;;
        *)
            echo "Proactive Mode - 基于 Claude Code 架构"
            echo ""
            echo "主动触发器:"
            echo "  - file_change     文件变化时建议"
            echo "  - code_pattern    代码模式检测"
            echo "  - time_based      时间触发"
            echo "  - system_state    系统状态变化"
            echo "  - user_behavior   用户行为学习"
            echo ""
            echo "用法:"
            echo "  $0 init                    - 初始化"
            echo "  $0 record <type> <detail> [context] [session] - 记录行为"
            echo "  $0 suggest <type> <context> <text> [confidence] [priority] - 生成建议"
            echo "  $0 respond <sugg_id> <Y/N> - 处理用户响应"
            echo "  $0 loop                    - 运行检查循环"
            echo "  $0 check [dir]             - 检查一次"
            echo "  $0 stats                   - 查看统计"
            echo "  $0 test                    - 测试功能"
            ;;
    esac
}

main "$@"
