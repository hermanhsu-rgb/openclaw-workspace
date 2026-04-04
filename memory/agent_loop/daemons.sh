#!/bin/bash
# daemons.sh - OpenClaw Background Daemons Manager
# 基于 Claude Code 架构：File Watcher, Memory Extractor, Indexer, Health Check, Sync

DAEMONS_DIR="/root/.openclaw/agent_loop/daemons"
DAEMONS_PID_FILE="$DAEMONS_DIR/daemons.pid"
DAEMONS_LOG="$DAEMONS_DIR/daemons.log"
CONFIG_FILE="/root/.openclaw/agent_loop/daemons_config.json"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 初始化守护进程系统
init_daemons() {
    echo "初始化 Background Daemons 系统..."
    mkdir -p "$DAEMONS_DIR"/{logs,pids,watchers,indexes}
    
    # 创建状态数据库
    sqlite3 "$DAEMONS_DIR/daemons.db" << 'EOF'
CREATE TABLE IF NOT EXISTS daemon_status (
    daemon_name TEXT PRIMARY KEY,
    status TEXT DEFAULT 'stopped',
    pid INTEGER,
    started_at TIMESTAMP,
    last_heartbeat TIMESTAMP,
    restart_count INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS file_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT,
    event_type TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS health_checks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    check_type TEXT,
    status TEXT,
    value TEXT,
    threshold TEXT,
    alert_sent INTEGER DEFAULT 0,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS daemon_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    daemon_name TEXT,
    level TEXT,
    message TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_file_events ON file_events(timestamp);
CREATE INDEX IF NOT EXISTS idx_health_checks ON health_checks(timestamp);
EOF
    
    # 初始化守护进程状态
    for daemon in file_watcher memory_extractor indexer health_check sync_daemon scheduler; do
        sqlite3 "$DAEMONS_DIR/daemons.db" "INSERT OR IGNORE INTO daemon_status (daemon_name, status) VALUES ('$daemon', 'stopped');"
    done
    
    echo "✅ Background Daemons 系统已初始化"
}

# 日志函数
log_daemon() {
    local daemon="$1"
    local level="$2"
    local message="$3"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$daemon] [$level] $message" >> "$DAEMONS_LOG"
    sqlite3 "$DAEMONS_DIR/daemons.db" "INSERT INTO daemon_logs (daemon_name, level, message) VALUES ('$daemon', '$level', '$(echo "$message" | sed "s/'/''/g")');"
}

# ==================== File Watcher Daemon ====================
file_watcher_daemon() {
    local daemon_name="file_watcher"
    log_daemon "$daemon_name" "INFO" "File Watcher Daemon 启动"
    
    # 更新状态
    sqlite3 "$DAEMONS_DIR/daemons.db" "UPDATE daemon_status SET status='running', pid=$$, started_at=CURRENT_TIMESTAMP, last_heartbeat=CURRENT_TIMESTAMP WHERE daemon_name='$daemon_name';"
    
    # 获取配置
    local watch_paths=$(jq -r '.daemons.file_watcher.watch_paths[]' "$CONFIG_FILE" 2>/dev/null | sed "s|~|$HOME|g")
    local ignore_patterns=$(jq -r '.daemons.file_watcher.ignore_patterns[]' "$CONFIG_FILE" 2>/dev/null | tr '\n' '|' | sed 's/|$//')
    local debounce_ms=$(jq -r '.daemons.file_watcher.debounce_ms // 500' "$CONFIG_FILE")
    
    log_daemon "$daemon_name" "INFO" "监控路径: $watch_paths"
    log_daemon "$daemon_name" "INFO" "忽略模式: $ignore_patterns"
    
    # 使用 inotifywait 监控文件变化
    if command -v inotifywait &> /dev/null; then
        while true; do
            # 更新心跳
            sqlite3 "$DAEMONS_DIR/daemons.db" "UPDATE daemon_status SET last_heartbeat=CURRENT_TIMESTAMP WHERE daemon_name='$daemon_name';"
            
            # 监控文件事件
            inotifywait -r -e create,modify,delete,move \
                --exclude "($ignore_patterns)" \
                --timeout "${debounce_ms}" \
                $watch_paths 2>/dev/null | while read path event file; do
                
                local full_path="$path$file"
                local event_type=$(echo "$event" | tr ',' '\n' | head -1 | tr -d ' ')
                
                # 记录事件
                sqlite3 "$DAEMONS_DIR/daemons.db" "INSERT INTO file_events (file_path, event_type) VALUES ('$full_path', '$event_type');"
                log_daemon "$daemon_name" "INFO" "检测到: $event_type - $full_path"
                
                # 触发钩子
                if [ -f ~/.openclaw/agent_loop/hooks.sh ]; then
                    source ~/.openclaw/agent_loop/hooks.sh
                    trig_event "on_file_change" "daemon-$daemon_name" "$full_path" "$event_type" > /dev/null 2>&1 || true
                fi
            done
            
            sleep 1
        done
    else
        log_daemon "$daemon_name" "ERROR" "inotifywait 未安装，使用轮询模式"
        # 轮询模式（备用）
        while true; do
            sqlite3 "$DAEMONS_DIR/daemons.db" "UPDATE daemon_status SET last_heartbeat=CURRENT_TIMESTAMP WHERE daemon_name='$daemon_name';"
            sleep 5
        done
    fi
}

# ==================== Memory Extractor Daemon ====================
memory_extractor_daemon() {
    local daemon_name="memory_extractor"
    log_daemon "$daemon_name" "INFO" "Memory Extractor Daemon 启动"
    
    sqlite3 "$DAEMONS_DIR/daemons.db" "UPDATE daemon_status SET status='running', pid=$$, started_at=CURRENT_TIMESTAMP, last_heartbeat=CURRENT_TIMESTAMP WHERE daemon_name='$daemon_name';"
    
    local schedule=$(jq -r '.daemons.memory_extractor.schedule // "0 */6 * * *"' "$CONFIG_FILE")
    local batch_size=$(jq -r '.daemons.memory_extractor.batch_size // 100' "$CONFIG_FILE")
    
    log_daemon "$daemon_name" "INFO" "执行计划: $schedule, 批次大小: $batch_size"
    
    while true; do
        sqlite3 "$DAEMONS_DIR/daemons.db" "UPDATE daemon_status SET last_heartbeat=CURRENT_TIMESTAMP WHERE daemon_name='$daemon_name';"
        
        # 检查是否应该执行（简单实现：每6小时）
        local current_hour=$(date +%H)
        if [ "$current_hour" = "00" ] || [ "$current_hour" = "06" ] || [ "$current_hour" = "12" ] || [ "$current_hour" = "18" ]; then
            log_daemon "$daemon_name" "INFO" "开始提取记忆..."
            
            # 分析会话历史
            local sessions=$(sqlite3 ~/.openclaw/agent_loop/state_machine/states.db "SELECT session_id, context FROM state_sessions WHERE updated_at > datetime('now', '-1 day') LIMIT $batch_size;" 2>/dev/null)
            
            local count=0
            while IFS='|' read -r session_id context; do
                [ -z "$session_id" ] && continue
                count=$((count + 1))
                
                # 提取关键信息（简化版）
                local extracted=$(echo "$context" | grep -oE '(关键|重要|记住|记录|任务|目标)[^，。]*' | head -5)
                
                if [ -n "$extracted" ]; then
                    log_daemon "$daemon_name" "INFO" "从会话 $session_id 提取到 $count 条记忆"
                    
                    # 保存到记忆系统
                    echo "$extracted" >> ~/.openclaw/workspace/memory/auto_extracted_$(date +%Y-%m-%d).md
                fi
            done <<< "$sessions"
            
            log_daemon "$daemon_name" "INFO" "记忆提取完成，处理了 $count 个会话"
        fi
        
        sleep 3600  # 每小时检查一次
    done
}

# ==================== Health Check Daemon ====================
health_check_daemon() {
    local daemon_name="health_check"
    log_daemon "$daemon_name" "INFO" "Health Check Daemon 启动"
    
    sqlite3 "$DAEMONS_DIR/daemons.db" "UPDATE daemon_status SET status='running', pid=$$, started_at=CURRENT_TIMESTAMP, last_heartbeat=CURRENT_TIMESTAMP WHERE daemon_name='$daemon_name';"
    
    local interval=$(jq -r '.daemons.health_check.interval_seconds // 300' "$CONFIG_FILE")
    local disk_warning=$(jq -r '.daemons.health_check.thresholds.disk_warning // 80' "$CONFIG_FILE")
    local disk_critical=$(jq -r '.daemons.health_check.thresholds.disk_critical // 90' "$CONFIG_FILE")
    
    log_daemon "$daemon_name" "INFO" "检查间隔: ${interval}秒"
    
    while true; do
        sqlite3 "$DAEMONS_DIR/daemons.db" "UPDATE daemon_status SET last_heartbeat=CURRENT_TIMESTAMP WHERE daemon_name='$daemon_name';"
        
        # 磁盘空间检查
        local disk_usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
        if [ "$disk_usage" -ge "$disk_critical" ]; then
            sqlite3 "$DAEMONS_DIR/daemons.db" "INSERT INTO health_checks (check_type, status, value, threshold) VALUES ('disk_space', 'CRITICAL', '$disk_usage', '$disk_critical');"
            log_daemon "$daemon_name" "CRITICAL" "磁盘使用率: ${disk_usage}% (阈值: ${disk_critical}%)"
        elif [ "$disk_usage" -ge "$disk_warning" ]; then
            sqlite3 "$DAEMONS_DIR/daemons.db" "INSERT INTO health_checks (check_type, status, value, threshold) VALUES ('disk_space', 'WARNING', '$disk_usage', '$disk_warning');"
            log_daemon "$daemon_name" "WARNING" "磁盘使用率: ${disk_usage}% (阈值: ${disk_warning}%)"
        fi
        
        # 内存检查
        local memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
        if [ "$memory_usage" -ge 90 ]; then
            sqlite3 "$DAEMONS_DIR/daemons.db" "INSERT INTO health_checks (check_type, status, value, threshold) VALUES ('memory_usage', 'CRITICAL', '$memory_usage', '90');"
            log_daemon "$daemon_name" "CRITICAL" "内存使用率: ${memory_usage}%"
        fi
        
        # API 连通性检查
        if [ -n "$TAVILY_API_KEY" ]; then
            local tavily_status=$(curl -s -o /dev/null -w "%{http_code}" "https://api.tavily.com/health" 2>/dev/null || echo "000")
            if [ "$tavily_status" != "200" ]; then
                log_daemon "$daemon_name" "WARNING" "Tavily API 连接异常 (状态码: $tavily_status)"
            fi
        fi
        
        # Skills 健康检查
        local skills_count=$(ls ~/.openclaw/workspace/skills/*/SKILL.md 2>/dev/null | wc -l)
        log_daemon "$daemon_name" "INFO" "Skills 数量: $skills_count"
        
        sleep "$interval"
    done
}

# ==================== Sync Daemon ====================
sync_daemon() {
    local daemon_name="sync_daemon"
    log_daemon "$daemon_name" "INFO" "Sync Daemon 启动"
    
    sqlite3 "$DAEMONS_DIR/daemons.db" "UPDATE daemon_status SET status='running', pid=$$, started_at=CURRENT_TIMESTAMP, last_heartbeat=CURRENT_TIMESTAMP WHERE daemon_name='$daemon_name';"
    
    local interval=$(jq -r '.daemons.sync_daemon.interval_seconds // 3600' "$CONFIG_FILE")
    
    while true; do
        sqlite3 "$DAEMONS_DIR/daemons.db" "UPDATE daemon_status SET last_heartbeat=CURRENT_TIMESTAMP WHERE daemon_name='$daemon_name';"
        
        log_daemon "$daemon_name" "INFO" "执行同步任务..."
        
        # GitHub 备份同步
        cd ~/.openclaw/workspace/memory 2>/dev/null && git push origin master 2>/dev/null && log_daemon "$daemon_name" "INFO" "GitHub 同步成功" || log_daemon "$daemon_name" "WARNING" "GitHub 同步失败"
        
        # 触发钩子
        if [ -f ~/.openclaw/agent_loop/hooks.sh ]; then
            source ~/.openclaw/agent_loop/hooks.sh
            trig_event "on_sync_complete" "daemon-$daemon_name" "github" > /dev/null 2>&1 || true
        fi
        
        sleep "$interval"
    done
}

# ==================== Scheduler Daemon ====================
scheduler_daemon() {
    local daemon_name="scheduler"
    log_daemon "$daemon_name" "INFO" "Scheduler Daemon 启动"
    
    sqlite3 "$DAEMONS_DIR/daemons.db" "UPDATE daemon_status SET status='running', pid=$$, started_at=CURRENT_TIMESTAMP, last_heartbeat=CURRENT_TIMESTAMP WHERE daemon_name='$daemon_name';"
    
    log_daemon "$daemon_name" "INFO" "定时任务调度器运行中..."
    
    while true; do
        sqlite3 "$DAEMONS_DIR/daemons.db" "UPDATE daemon_status SET last_heartbeat=CURRENT_TIMESTAMP WHERE daemon_name='$daemon_name';"
        
        local current_time=$(date +%H:%M)
        local current_minute=$(date +%M)
        
        # 检查定时任务（简化版）
        case "$current_time" in
            "08:00")
                log_daemon "$daemon_name" "INFO" "执行晨间推送"
                ~/.openclaw/agent_loop_morning_push.sh > /dev/null 2>&1 &
                ;;
            "03:00")
                log_daemon "$daemon_name" "INFO" "执行自动备份"
                ~/.openclaw/auto_updater.sh > /dev/null 2>&1 &
                ;;
            "03:30")
                log_daemon "$daemon_name" "INFO" "执行 Skills 更新 (Batch 1)"
                ~/.openclaw/skills_auto_update.sh batch1 > /dev/null 2>&1 &
                ;;
            "04:00")
                log_daemon "$daemon_name" "INFO" "执行 Skills 更新 (Batch 2)"
                ~/.openclaw/skills_auto_update.sh batch2 > /dev/null 2>&1 &
                ;;
        esac
        
        sleep 60  # 每分钟检查一次
    done
}

# ==================== Daemon Manager ====================

start_daemon() {
    local daemon_name="$1"
    
    # 检查是否已在运行
    local existing_pid=$(sqlite3 "$DAEMONS_DIR/daemons.db" "SELECT pid FROM daemon_status WHERE daemon_name='$daemon_name' AND status='running';")
    if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
        echo -e "${YELLOW}⚠️ $daemon_name 已经在运行 (PID: $existing_pid)${NC}"
        return 0
    fi
    
    # 启动守护进程
    case "$daemon_name" in
        "file_watcher")
            file_watcher_daemon &
            ;;
        "memory_extractor")
            memory_extractor_daemon &
            ;;
        "health_check")
            health_check_daemon &
            ;;
        "sync_daemon")
            sync_daemon &
            ;;
        "scheduler")
            scheduler_daemon &
            ;;
        "all")
            start_all_daemons
            return 0
            ;;
        *)
            echo -e "${RED}❌ 未知的守护进程: $daemon_name${NC}"
            return 1
            ;;
    esac
    
    local pid=$!
    echo $pid > "$DAEMONS_DIR/pids/${daemon_name}.pid"
    echo -e "${GREEN}✅ $daemon_name 已启动 (PID: $pid)${NC}"
}

start_all_daemons() {
    echo "启动所有守护进程..."
    start_daemon "file_watcher"
    start_daemon "memory_extractor"
    start_daemon "health_check"
    start_daemon "sync_daemon"
    start_daemon "scheduler"
    
    # 保存主 PID
    echo $$ > "$DAEMONS_PID_FILE"
    echo -e "${GREEN}✅ 所有守护进程已启动${NC}"
}

stop_daemon() {
    local daemon_name="$1"
    
    if [ "$daemon_name" = "all" ]; then
        stop_all_daemons
        return 0
    fi
    
    local pid=$(cat "$DAEMONS_DIR/pids/${daemon_name}.pid" 2>/dev/null)
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null
        sqlite3 "$DAEMONS_DIR/daemons.db" "UPDATE daemon_status SET status='stopped', pid=NULL WHERE daemon_name='$daemon_name';"
        rm -f "$DAEMONS_DIR/pids/${daemon_name}.pid"
        echo -e "${GREEN}✅ $daemon_name 已停止${NC}"
    else
        echo -e "${YELLOW}⚠️ $daemon_name 未在运行${NC}"
    fi
}

stop_all_daemons() {
    echo "停止所有守护进程..."
    if [ -d "$DAEMONS_DIR/pids" ]; then
        for pid_file in "$DAEMONS_DIR/pids"/*.pid; do
            [ -f "$pid_file" ] || continue
            local daemon_name=$(basename "$pid_file" .pid)
            stop_daemon "$daemon_name"
        done
    fi
    rm -f "$DAEMONS_PID_FILE"
    echo -e "${GREEN}✅ 所有守护进程已停止${NC}"
}

status_daemons() {
    echo "=== Background Daemons 状态 ==="
    echo ""
    sqlite3 "$DAEMONS_DIR/daemons.db" << 'EOF'
SELECT 
    daemon_name,
    status,
    pid,
    strftime('%Y-%m-%d %H:%M', started_at) as started,
    strftime('%Y-%m-%d %H:%M', last_heartbeat) as heartbeat,
    restart_count
FROM daemon_status
ORDER BY daemon_name;
EOF
    
    echo ""
    echo "运行中的进程:"
    if [ -d "$DAEMONS_DIR/pids" ]; then
        for pid_file in "$DAEMONS_DIR/pids"/*.pid; do
            [ -f "$pid_file" ] || continue
            local daemon_name=$(basename "$pid_file" .pid)
            local pid=$(cat "$pid_file")
            if kill -0 "$pid" 2>/dev/null; then
                echo "  ✅ $daemon_name (PID: $pid)"
            else
                echo "  ❌ $daemon_name (PID: $pid - 已失效)"
            fi
        done
    fi
}

show_logs() {
    local daemon_name="${1:-}"
    local lines="${2:-50}"
    
    if [ -n "$daemon_name" ]; then
        sqlite3 "$DAEMONS_DIR/daemons.db" << EOF
SELECT strftime('%Y-%m-%d %H:%M:%S', timestamp) as time, level, message
FROM daemon_logs
WHERE daemon_name = '$daemon_name'
ORDER BY timestamp DESC
LIMIT $lines;
EOF
    else
        tail -n "$lines" "$DAEMONS_LOG" 2>/dev/null
    fi
}

# 主入口
main() {
    case "$1" in
        "init")
            init_daemons
            ;;
        "start")
            start_daemon "$2"
            ;;
        "stop")
            stop_daemon "$2"
            ;;
        "restart")
            stop_daemon "$2"
            sleep 1
            start_daemon "$2"
            ;;
        "status")
            status_daemons
            ;;
        "logs")
            show_logs "$2" "$3"
            ;;
        *)
            echo "Background Daemons Manager - 基于 Claude Code 架构"
            echo ""
            echo "可用守护进程:"
            echo "  - file_watcher      文件监控"
            echo "  - memory_extractor  记忆提取"
            echo "  - health_check      健康检查"
            echo "  - sync_daemon       同步守护"
            echo "  - scheduler         定时调度"
            echo "  - all               全部"
            echo ""
            echo "用法:"
            echo "  $0 init                    - 初始化"
            echo "  $0 start <daemon|all>      - 启动守护进程"
            echo "  $0 stop <daemon|all>       - 停止守护进程"
            echo "  $0 restart <daemon>        - 重启守护进程"
            echo "  $0 status                  - 查看状态"
            echo "  $0 logs [daemon] [lines]   - 查看日志"
            ;;
    esac
}

main "$@"
