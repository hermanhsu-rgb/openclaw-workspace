#!/bin/bash
# observability.sh - 可观测性系统 (Tracing & Metrics)

OBS_DIR="/root/.openclaw/agent_loop/observability"
DB_FILE="$OBS_DIR/traces.db"

# 初始化可观测性系统
init_observability() {
    mkdir -p "$OBS_DIR"
    
    # 创建 SQLite 数据库
    sqlite3 "$DB_FILE" << 'EOF'
CREATE TABLE IF NOT EXISTS traces (
    trace_id TEXT PRIMARY KEY,
    session_id TEXT,
    start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMP,
    duration_ms INTEGER,
    status TEXT,
    user_input TEXT,
    final_output TEXT,
    error_message TEXT
);

CREATE TABLE IF NOT EXISTS spans (
    span_id TEXT PRIMARY KEY,
    trace_id TEXT,
    parent_span_id TEXT,
    name TEXT,
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    duration_ms INTEGER,
    status TEXT,
    attributes TEXT,
    FOREIGN KEY (trace_id) REFERENCES traces(trace_id)
);

CREATE TABLE IF NOT EXISTS metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metric_name TEXT,
    metric_value REAL,
    labels TEXT
);

CREATE INDEX IF NOT EXISTS idx_traces_session ON traces(session_id);
CREATE INDEX IF NOT EXISTS idx_spans_trace ON spans(trace_id);
CREATE INDEX IF NOT EXISTS idx_metrics_time ON metrics(timestamp);
EOF
    
    echo "✅ 可观测性系统已初始化"
    echo "数据库: $DB_FILE"
}

# 开始追踪
start_trace() {
    local session_id="$1"
    local user_input="$2"
    local trace_id=$(uuidgen 2>/dev/null || echo "trace-$(date +%s)-$$")
    
    sqlite3 "$DB_FILE" << EOF
INSERT INTO traces (trace_id, session_id, status, user_input)
VALUES ('$trace_id', '$session_id', 'running', '$(echo "$user_input" | sed "s/'/''/g")');
EOF
    
    echo "$trace_id"
}

# 结束追踪
end_trace() {
    local trace_id="$1"
    local status="$2"
    local output="${3:-}"
    local error="${4:-}"
    
    sqlite3 "$DB_FILE" << EOF
UPDATE traces 
SET end_time = CURRENT_TIMESTAMP,
    duration_ms = (julianday('now') - julianday(start_time)) * 86400000,
    status = '$status',
    final_output = '$(echo "$output" | sed "s/'/''/g")',
    error_message = '$(echo "$error" | sed "s/'/''/g")'
WHERE trace_id = '$trace_id';
EOF
}

# 记录 Span
record_span() {
    local trace_id="$1"
    local span_name="$2"
    local parent_span_id="${3:-NULL}"
    local attributes="${4:-{}}"
    local span_id=$(uuidgen 2>/dev/null || echo "span-$(date +%s)-$$")
    
    sqlite3 "$DB_FILE" << EOF
INSERT INTO spans (span_id, trace_id, parent_span_id, name, start_time, status, attributes)
VALUES ('$span_id', '$trace_id', '$parent_span_id', '$span_name', CURRENT_TIMESTAMP, 'running', '$(echo "$attributes" | sed "s/'/''/g")');
EOF
    
    echo "$span_id"
}

# 结束 Span
end_span() {
    local span_id="$1"
    local status="${2:-completed}"
    
    sqlite3 "$DB_FILE" << EOF
UPDATE spans 
SET end_time = CURRENT_TIMESTAMP,
    duration_ms = (julianday('now') - julianday(start_time)) * 86400000,
    status = '$status'
WHERE span_id = '$span_id';
EOF
}

# 记录指标
record_metric() {
    local name="$1"
    local value="$2"
    local labels="${3:-{}}"
    
    sqlite3 "$DB_FILE" << EOF
INSERT INTO metrics (metric_name, metric_value, labels)
VALUES ('$name', $value, '$(echo "$labels" | sed "s/'/''/g")');
EOF
}

# 获取追踪统计
trace_stats() {
    echo "=== Agent Loop 追踪统计 ==="
    echo ""
    
    echo "总追踪数:"
    sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM traces;"
    
    echo ""
    echo "状态分布:"
    sqlite3 "$DB_FILE" "SELECT status, COUNT(*) FROM traces GROUP BY status;"
    
    echo ""
    echo "平均执行时间 (ms):"
    sqlite3 "$DB_FILE" "SELECT AVG(duration_ms) FROM traces WHERE duration_ms IS NOT NULL;"
    
    echo ""
    echo "最近 5 次追踪:"
    sqlite3 "$DB_FILE" << 'EOF'
SELECT trace_id, status, duration_ms, 
       strftime('%Y-%m-%d %H:%M', start_time) as time
FROM traces 
ORDER BY start_time DESC 
LIMIT 5;
EOF
}

# 导出追踪详情
export_trace() {
    local trace_id="$1"
    
    echo "=== 追踪详情: $trace_id ==="
    sqlite3 "$DB_FILE" << EOF
SELECT * FROM traces WHERE trace_id = '$trace_id';
EOF
    
    echo ""
    echo "Spans:"
    sqlite3 "$DB_FILE" << EOF
SELECT span_id, name, duration_ms, status 
FROM spans 
WHERE trace_id = '$trace_id' 
ORDER BY start_time;
EOF
}

# 主入口
main() {
    case "$1" in
        "init")
            init_observability
            ;;
        "start")
            start_trace "$2" "$3"
            ;;
        "end")
            end_trace "$2" "$3" "$4" "$5"
            ;;
        "span-start")
            record_span "$2" "$3" "$4" "$5"
            ;;
        "span-end")
            end_span "$2" "$3"
            ;;
        "metric")
            record_metric "$2" "$3" "$4"
            ;;
        "stats")
            trace_stats
            ;;
        "export")
            export_trace "$2"
            ;;
        *)
            echo "可观测性系统"
            echo ""
            echo "用法:"
            echo "  $0 init                           - 初始化"
            echo "  $0 start <session_id> <input>     - 开始追踪"
            echo "  $0 end <trace_id> <status> [output] [error] - 结束追踪"
            echo "  $0 span-start <trace_id> <name> [parent] [attrs] - 开始 Span"
            echo "  $0 span-end <span_id> [status]    - 结束 Span"
            echo "  $0 metric <name> <value> [labels] - 记录指标"
            echo "  $0 stats                          - 统计信息"
            echo "  $0 export <trace_id>              - 导出追踪详情"
            ;;
    esac
}

main "$@"
