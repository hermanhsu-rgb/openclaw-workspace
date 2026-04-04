#!/bin/bash
# extract_memories.sh - OpenClaw Extract Memories
# 基于 Claude Code 架构：后台提取和整理记忆

EXTRACT_DIR="/root/.openclaw/agent_loop/extract_memories"
CONFIG_FILE="/root/.openclaw/agent_loop/extract_memories_config.json"
MEMORIES_DB="$EXTRACT_DIR/memories.db"
EXTRACTED_DIR="~/.openclaw/workspace/memory/extracted"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 初始化记忆提取系统
init_extract_memories() {
    echo "初始化 Extract Memories 系统..."
    mkdir -p "$EXTRACT_DIR"/{raw,processed,archived}
    mkdir -p "$EXTRACTED_DIR"
    
    # 创建记忆数据库
    sqlite3 "$MEMORIES_DB" << 'EOF'
CREATE TABLE IF NOT EXISTS raw_conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    role TEXT,  -- user / assistant
    content TEXT,
    processed INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS extracted_memories (
    memory_id TEXT PRIMARY KEY,
    memory_type TEXT,
    content TEXT,
    confidence REAL,
    context TEXT,
    source_session TEXT,
    extracted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_accessed TIMESTAMP,
    access_count INTEGER DEFAULT 0,
    status TEXT DEFAULT 'active'  -- active, archived, deleted
);

CREATE TABLE IF NOT EXISTS memory_relationships (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_memory TEXT,
    to_memory TEXT,
    relationship_type TEXT,
    strength REAL,
    FOREIGN KEY (from_memory) REFERENCES extracted_memories(memory_id),
    FOREIGN KEY (to_memory) REFERENCES extracted_memories(memory_id)
);

CREATE TABLE IF NOT EXISTS extraction_stats (
    date TEXT PRIMARY KEY,
    conversations_processed INTEGER DEFAULT 0,
    memories_extracted INTEGER DEFAULT 0,
    facts INTEGER DEFAULT 0,
    preferences INTEGER DEFAULT 0,
    decisions INTEGER DEFAULT 0,
    tasks INTEGER DEFAULT 0,
    relationships INTEGER DEFAULT 0,
    patterns INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_conversations_session ON raw_conversations(session_id);
CREATE INDEX IF NOT EXISTS idx_conversations_processed ON raw_conversations(processed);
CREATE INDEX IF NOT EXISTS idx_memories_type ON extracted_memories(memory_type);
CREATE INDEX IF NOT EXISTS idx_memories_status ON extracted_memories(status);
CREATE INDEX IF NOT EXISTS idx_memories_extracted ON extracted_memories(extracted_at);
EOF
    
    echo "✅ Extract Memories 系统已初始化"
}

# 记录对话
record_conversation() {
    local session_id="${1:-default}"
    local role="$2"
    local content="$3"
    
    sqlite3 "$MEMORIES_DB" << EOF
INSERT INTO raw_conversations (session_id, role, content)
VALUES ('$session_id', '$role', '$(echo "$content" | sed "s/'/''/g")');
EOF
}

# 基于规则提取记忆
extract_by_rules() {
    local content="$1"
    local memories=""
    
    # 提取偏好
    if echo "$content" | grep -qE "(喜欢|偏好|习惯|最爱)"; then
        local pref=$(echo "$content" | grep -oE "(喜欢|偏好|习惯|最爱)[^，。]*" | head -1)
        if [ -n "$pref" ]; then
            memories="${memories}preference|$pref|0.8\n"
        fi
    fi
    
    # 提取决策
    if echo "$content" | grep -qE "(决定|选择|选定|确定使用)"; then
        local decision=$(echo "$content" | grep -oE "(决定|选择|选定|确定使用)[^，。]*" | head -1)
        if [ -n "$decision" ]; then
            memories="${memories}decision|$decision|0.75\n"
        fi
    fi
    
    # 提取任务
    if echo "$content" | grep -qE "(需要|必须|应该|计划|待办)"; then
        local task=$(echo "$content" | grep -oE "(需要|必须|应该|计划|待办)[^，。]*" | head -1)
        if [ -n "$task" ]; then
            memories="${memories}task|$task|0.7\n"
        fi
    fi
    
    # 提取事实
    if echo "$content" | grep -qE "(配置在|路径是|使用|基于)"; then
        local fact=$(echo "$content" | grep -oE "(配置在|路径是|使用|基于)[^，。]*" | head -1)
        if [ -n "$fact" ]; then
            memories="${memories}fact|$fact|0.85\n"
        fi
    fi
    
    echo -e "$memories"
}

# 保存提取的记忆
save_memory() {
    local memory_type="$1"
    local content="$2"
    local confidence="$3"
    local context="$4"
    local source_session="${5:-default}"
    local memory_id="mem-$(date +%s)-$RANDOM"
    
    # 检查是否已存在相似记忆
    local existing=$(sqlite3 "$MEMORIES_DB" << EOF
SELECT memory_id FROM extracted_memories 
WHERE memory_type = '$memory_type' 
AND content LIKE '%$(echo "$content" | sed "s/'/''/g" | cut -c1-30)%'
AND status = 'active'
LIMIT 1;
EOF
)
    
    if [ -n "$existing" ]; then
        # 更新现有记忆
        sqlite3 "$MEMORIES_DB" << EOF
UPDATE extracted_memories 
SET confidence = MAX(confidence, $confidence),
    last_accessed = CURRENT_TIMESTAMP,
    access_count = access_count + 1
WHERE memory_id = '$existing';
EOF
        echo "updated:$existing"
    else
        # 插入新记忆
        sqlite3 "$MEMORIES_DB" << EOF
INSERT INTO extracted_memories (memory_id, memory_type, content, confidence, context, source_session)
VALUES ('$memory_id', '$memory_type', '$(echo "$content" | sed "s/'/''/g")', $confidence, '$(echo "$context" | sed "s/'/''/g")', '$source_session');
EOF
        
        # 同时保存到 markdown 文件
        save_to_markdown "$memory_type" "$content" "$confidence"
        
        echo "created:$memory_id"
    fi
}

# 保存到 markdown 文件
save_to_markdown() {
    local memory_type="$1"
    local content="$2"
    local confidence="$3"
    
    local filename="$EXTRACTED_DIR/${memory_type}s_$(date +%Y-%m).md"
    
    # 创建文件头（如果不存在）
    if [ ! -f "$filename" ]; then
        echo "# ${memory_type}s - $(date +%Y年%m月)" > "$filename"
        echo "" >> "$filename"
        echo "自动提取的记忆记录" >> "$filename"
        echo "" >> "$filename"
    fi
    
    # 追加记忆
    echo "## $(date '+%Y-%m-%d %H:%M')" >> "$filename"
    echo "" >> "$filename"
    echo "- **内容**: $content" >> "$filename"
    echo "- **置信度**: ${confidence}" >> "$filename"
    echo "" >> "$filename"
}

# 处理未处理的对话
process_conversations() {
    local batch_size="${1:-50}"
    
    echo "处理未提取的对话..."
    
    # 获取未处理的对话
    local conversations=$(sqlite3 "$MEMORIES_DB" << EOF
SELECT id, session_id, role, content 
FROM raw_conversations 
WHERE processed = 0 
ORDER BY timestamp 
LIMIT $batch_size;
EOF
)
    
    local processed_count=0
    local extracted_count=0
    local type_counts="facts:0,preferences:0,decisions:0,tasks:0,relationships:0,patterns:0"
    
    while IFS='|' read -r id session_id role content; do
        [ -z "$id" ] && continue
        
        processed_count=$((processed_count + 1))
        
        # 提取记忆
        local memories=$(extract_by_rules "$content")
        
        while IFS='|' read -r mem_type mem_content mem_confidence; do
            [ -z "$mem_type" ] && continue
            
            local result=$(save_memory "$mem_type" "$mem_content" "$mem_confidence" "$content" "$session_id")
            
            if echo "$result" | grep -q "created"; then
                extracted_count=$((extracted_count + 1))
                
                # 更新类型计数
                case "$mem_type" in
                    "fact") type_counts=$(echo "$type_counts" | sed 's/facts:\([0-9]*\)/facts:\1+1/') ;;
                    "preference") type_counts=$(echo "$type_counts" | sed 's/preferences:\([0-9]*\)/preferences:\1+1/') ;;
                    "decision") type_counts=$(echo "$type_counts" | sed 's/decisions:\([0-9]*\)/decisions:\1+1/') ;;
                    "task") type_counts=$(echo "$type_counts" | sed 's/tasks:\([0-9]*\)/tasks:\1+1/') ;;
                    "relationship") type_counts=$(echo "$type_counts" | sed 's/relationships:\([0-9]*\)/relationships:\1+1/') ;;
                    "pattern") type_counts=$(echo "$type_counts" | sed 's/patterns:\([0-9]*\)/patterns:\1+1/') ;;
                esac
            fi
        done <<< "$memories"
        
        # 标记为已处理
        sqlite3 "$MEMORIES_DB" "UPDATE raw_conversations SET processed = 1 WHERE id = $id;"
        
    done <<< "$conversations"
    
    # 更新统计
    local today=$(date +%Y-%m-%d)
    sqlite3 "$MEMORIES_DB" << EOF
INSERT INTO extraction_stats (date, conversations_processed, memories_extracted)
VALUES ('$today', $processed_count, $extracted_count)
ON CONFLICT(date) DO UPDATE SET 
    conversations_processed = conversations_processed + $processed_count,
    memories_extracted = memories_extracted + $extracted_count;
EOF
    
    echo "处理完成: $processed_count 条对话，提取 $extracted_count 条记忆"
}

# 搜索记忆
search_memories() {
    local query="$1"
    local memory_type="${2:-}"
    local limit="${3:-10}"
    
    echo "=== 搜索记忆: '$query' ==="
    echo ""
    
    local type_filter=""
    if [ -n "$memory_type" ]; then
        type_filter="AND memory_type = '$memory_type'"
    fi
    
    sqlite3 "$MEMORIES_DB" << EOF
SELECT memory_type, substr(content, 1, 80) as content, confidence, 
       strftime('%Y-%m-%d', extracted_at) as date
FROM extracted_memories 
WHERE status = 'active' 
AND (content LIKE '%$(echo "$query" | sed "s/'/''/g")%' $type_filter)
ORDER BY confidence DESC, access_count DESC
LIMIT $limit;
EOF
}

# 列出记忆
list_memories() {
    local memory_type="${1:-}"
    local limit="${2:-20}"
    
    echo "=== 记忆列表 ==="
    echo ""
    
    local type_filter=""
    if [ -n "$memory_type" ]; then
        type_filter="AND memory_type = '$memory_type'"
    fi
    
    sqlite3 "$MEMORIES_DB" << EOF
SELECT memory_type, substr(content, 1, 60) as content, 
       round(confidence, 2) as conf,
       access_count as visits,
       strftime('%Y-%m-%d', extracted_at) as date
FROM extracted_memories 
WHERE status = 'active' $type_filter
ORDER BY extracted_at DESC
LIMIT $limit;
EOF
}

# 生成记忆摘要
 generate_summary() {
    echo "=== 记忆摘要 ==="
    echo ""
    
    echo "按类型统计:"
    sqlite3 "$MEMORIES_DB" << EOF
SELECT memory_type, COUNT(*) as count, 
       ROUND(AVG(confidence), 2) as avg_confidence
FROM extracted_memories 
WHERE status = 'active'
GROUP BY memory_type
ORDER BY count DESC;
EOF
    
    echo ""
    echo "最近的提取活动:"
    sqlite3 "$MEMORIES_DB" << EOF
SELECT date, conversations_processed, memories_extracted
FROM extraction_stats
ORDER BY date DESC
LIMIT 7;
EOF
    
    echo ""
    echo "高置信度记忆 (Top 5):"
    sqlite3 "$MEMORIES_DB" << EOF
SELECT memory_type, substr(content, 1, 50), confidence
FROM extracted_memories
WHERE status = 'active'
ORDER BY confidence DESC
LIMIT 5;
EOF
}

# 清理重复记忆
 deduplicate_memories() {
    echo "清理重复记忆..."
    
    # 查找相似的记忆并合并
    local duplicates=$(sqlite3 "$MEMORIES_DB" << EOF
SELECT m1.memory_id, m2.memory_id
FROM extracted_memories m1
JOIN extracted_memories m2 ON m1.memory_type = m2.memory_type
AND m1.memory_id != m2.memory_id
AND m1.content LIKE '%' || substr(m2.content, 1, 20) || '%'
AND m1.status = 'active' AND m2.status = 'active'
LIMIT 100;
EOF
)
    
    local merged=0
    while IFS='|' read -r id1 id2; do
        [ -z "$id1" ] && continue
        
        # 归档较旧的那个
        sqlite3 "$MEMORIES_DB" "UPDATE extracted_memories SET status = 'archived' WHERE memory_id = '$id2';"
        merged=$((merged + 1))
    done <<< "$duplicates"
    
    echo "合并了 $merged 条重复记忆"
}

# 运行记忆提取守护进程
 extraction_daemon() {
    echo "🧠 Extract Memories Daemon 启动..."
    echo "每 4 小时自动提取一次"
    echo "按 Ctrl+C 停止"
    echo ""
    
    while true; do
        local current_hour=$(date +%H)
        if [ "$current_hour" = "00" ] || [ "$current_hour" = "04" ] || [ "$current_hour" = "08" ] || [ "$current_hour" = "12" ] || [ "$current_hour" = "16" ] || [ "$current_hour" = "20" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M')] 开始提取记忆..."
            process_conversations 50
            echo "[$(date '+%Y-%m-%d %H:%M')] 提取完成"
        fi
        
        sleep 3600  # 每小时检查一次
    done
}

# 测试记忆提取
 test_extraction() {
    echo "=== 测试 Extract Memories ==="
    echo ""
    
    echo "测试 1: 记录对话"
    record_conversation "test-session" "user" "我喜欢使用 Tavily 搜索，因为它免费"
    record_conversation "test-session" "assistant" "好的，我记住了您偏好使用 Tavily"
    record_conversation "test-session" "user" "决定每天凌晨 3 点自动更新 skills"
    record_conversation "test-session" "user" "需要配置 GitHub 推送"
    
    echo ""
    echo "测试 2: 提取记忆"
    process_conversations 10
    
    echo ""
    echo "测试 3: 查看记忆列表"
    list_memories
    
    echo ""
    echo "测试 4: 搜索记忆"
    search_memories "Tavily"
    
    echo ""
    echo "测试完成！"
}

# 主入口
 main() {
    case "$1" in
        "init")
            init_extract_memories
            ;;
        "record")
            record_conversation "$2" "$3" "$4"
            ;;
        "extract"|"process")
            process_conversations "$2"
            ;;
        "search")
            search_memories "$2" "$3" "$4"
            ;;
        "list")
            list_memories "$2" "$3"
            ;;
        "summary")
            generate_summary
            ;;
        "dedup")
            deduplicate_memories
            ;;
        "daemon")
            extraction_daemon
            ;;
        "test")
            test_extraction
            ;;
        *)
            echo "Extract Memories - 基于 Claude Code 架构"
            echo ""
            echo "记忆类型:"
            echo "  - facts          客观事实"
            echo "  - preferences    用户偏好"
            echo "  - decisions      决策记录"
            echo "  - tasks          待办任务"
            echo "  - relationships  实体关系"
            echo "  - patterns       行为模式"
            echo ""
            echo "用法:"
            echo "  $0 init                          - 初始化"
            echo "  $0 record <session> <role> <content> - 记录对话"
            echo "  $0 extract [batch_size]          - 提取记忆"
            echo "  $0 search <query> [type] [limit] - 搜索记忆"
            echo "  $0 list [type] [limit]           - 列出记忆"
            echo "  $0 summary                       - 记忆摘要"
            echo "  $0 dedup                         - 清理重复"
            echo "  $0 daemon                        - 运行守护进程"
            echo "  $0 test                          - 测试功能"
            ;;
    esac
}

main "$@"
