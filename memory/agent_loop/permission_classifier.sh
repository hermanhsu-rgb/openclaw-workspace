#!/bin/bash
# permission_classifier.sh - OpenClaw Permission Classifier
# 基于 Claude Code 架构，LLM 驱动的风险分析

PERMISSION_DIR="/root/.openclaw/agent_loop/permission_classifier"
CONFIG_FILE="/root/.openclaw/agent_loop/permission_classifier_config.json"
AUDIT_LOG="$PERMISSION_DIR/audit.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 初始化权限分类器
init_permission_classifier() {
    echo "初始化 Permission Classifier..."
    mkdir -p "$PERMISSION_DIR"
    
    # 创建审计日志数据库
    sqlite3 "$PERMISSION_DIR/audit.db" << 'EOF'
CREATE TABLE IF NOT EXISTS permission_decisions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    command TEXT,
    context TEXT,
    risk_level TEXT,
    reasoning TEXT,
    auto_executed INTEGER,
    user_confirmed INTEGER,
    user_reason TEXT,
    llm_analysis TEXT,
    execution_time_ms INTEGER
);

CREATE TABLE IF NOT EXISTS risk_cache (
    command_hash TEXT PRIMARY KEY,
    command_pattern TEXT,
    risk_level TEXT,
    reasoning TEXT,
    cached_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    hit_count INTEGER DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_decisions_time ON permission_decisions(timestamp);
CREATE INDEX IF NOT EXISTS idx_decisions_risk ON permission_decisions(risk_level);
CREATE INDEX IF NOT EXISTS idx_cache_hash ON risk_cache(command_hash);
EOF
    
    echo "✅ Permission Classifier 已初始化"
}

# 计算命令哈希
hash_command() {
    echo "$1" | md5sum | cut -d' ' -f1
}

# 检查缓存
check_cache() {
    local command="$1"
    local hash=$(hash_command "$command")
    
    local cached=$(sqlite3 "$PERMISSION_DIR/audit.db" << EOF
SELECT risk_level, reasoning FROM risk_cache WHERE command_hash = '$hash';
EOF
)
    
    if [ -n "$cached" ]; then
        # 更新命中次数
        sqlite3 "$PERMISSION_DIR/audit.db" "UPDATE risk_cache SET hit_count = hit_count + 1 WHERE command_hash = '$hash';"
        echo "$cached"
        return 0
    fi
    
    return 1
}

# 缓存结果
cache_result() {
    local command="$1"
    local risk_level="$2"
    local reasoning="$3"
    local hash=$(hash_command "$command")
    
    sqlite3 "$PERMISSION_DIR/audit.db" << EOF
INSERT OR REPLACE INTO risk_cache (command_hash, command_pattern, risk_level, reasoning)
VALUES ('$hash', '$(echo "$command" | sed "s/'/''/g")', '$risk_level', '$(echo "$reasoning" | sed "s/'/''/g")');
EOF
}

# 基于规则的快速分类
classify_by_rules() {
    local command="$1"
    local risk_level="safe"
    local reasoning="基于规则分析: "
    
    # 检查关键命令 (严格匹配)
    if echo "$command" | grep -qE "(^rm -rf /$|^rm -rf /\*$|^rm -rf /\.\*$|mkfs\.?ext|mkfs\.?xfs|^dd if=/dev/zero of=/dev|^dd if=/dev/urandom|> /dev/sda|> /dev/hda|:\(\)\{ :\|:\& };:|^:%s/.*/)"; then
        risk_level="critical"
        reasoning="检测到极度危险的系统破坏命令"
        echo "$risk_level|$reasoning"
        return
    fi
    
    # 检查系统级递归删除
    if echo "$command" | grep -qE "(rm -rf /(bin|sbin|etc|boot|usr|lib|lib64|proc|sys|dev)($|/))"; then
        risk_level="critical"
        reasoning="尝试删除系统关键目录"
        echo "$risk_level|$reasoning"
        return
    fi
    
    # 检查删除命令
    if echo "$command" | grep -qE "^rm -rf|^rm -f /|^rm -r /"; then
        risk_level="high"
        reasoning="递归强制删除操作"
        echo "$risk_level|$reasoning"
        return
    fi
    
    # 检查系统命令
    if echo "$command" | grep -qE "(shutdown|reboot|halt|poweroff|systemctl stop|service stop)"; then
        risk_level="high"
        reasoning="系统控制命令，可能影响服务可用性"
        echo "$risk_level|$reasoning"
        return
    fi
    
    # 检查网络配置
    if echo "$command" | grep -qE "(iptables|ufw|firewall-cmd)"; then
        risk_level="high"
        reasoning="防火墙配置修改，可能影响网络连接"
        echo "$risk_level|$reasoning"
        return
    fi
    
    # 检查挂载操作
    if echo "$command" | grep -qE "(mount|umount|fdisk|parted)"; then
        risk_level="high"
        reasoning="磁盘挂载/分区操作"
        echo "$risk_level|$reasoning"
        return
    fi
    
    # 检查写操作
    if echo "$command" | grep -qE "(> /etc/|> /boot/|> /bin/|> /sbin/)"; then
        risk_level="critical"
        reasoning="向系统关键目录写入数据"
        echo "$risk_level|$reasoning"
        return
    fi
    
    # 检查通配符删除
    if echo "$command" | grep -qE "rm.*\*|rm.*\.\*"; then
        risk_level="medium"
        reasoning="使用通配符的删除操作，范围不确定"
        echo "$risk_level|$reasoning"
        return
    fi
    
    # 检查文件修改
    if echo "$command" | grep -qE "(chmod|chown|mv /etc/|cp /etc/)"; then
        risk_level="medium"
        reasoning="系统文件权限或所有权修改"
        echo "$risk_level|$reasoning"
        return
    fi
    
    # 检查只读命令
    if echo "$command" | grep -qE "^(ls|cat|echo|grep|head|tail|wc|date|pwd|whoami|ps|df|du|free|uptime|uname|hostname|id|groups|find|locate|which|whereis|file|stat|lsof|netstat|ss|ping|curl|wget|tar|gzip|gunzip|zip|unzip)\b"; then
        risk_level="safe"
        reasoning="只读或信息查询命令"
        echo "$risk_level|$reasoning"
        return
    fi
    
    # 检查写入操作
    if echo "$command" | grep -qE "(cp|mv|mkdir|touch|rsync|scp)"; then
        risk_level="low"
        reasoning="文件写入操作"
        echo "$risk_level|$reasoning"
        return
    fi
    
    # 检查安装命令
    if echo "$command" | grep -qE "(npm install|pip install|apt install|yum install|brew install)"; then
        risk_level="low"
        reasoning="软件包安装操作"
        echo "$risk_level|$reasoning"
        return
    fi
    
    # 检查 Git 操作
    if echo "$command" | grep -qE "^git (clone|pull|fetch|checkout|merge)"; then
        risk_level="low"
        reasoning="Git 代码操作"
        echo "$risk_level|$reasoning"
        return
    fi
    
    # 默认
    risk_level="medium"
    reasoning="未明确分类的命令，需要进一步分析"
    echo "$risk_level|$reasoning"
}

# LLM 分析
llm_classify() {
    local command="$1"
    local context="${2:-}"
    local api_key="${GEMINI_API_KEY:-}"
    
    if [ -z "$api_key" ]; then
        echo "unknown|LLM API Key 未设置"
        return 1
    fi
    
    local prompt="Analyze this command for security risk:\n\nCommand: $command\nContext: $context\n\nRespond ONLY with JSON format:\n{\n  \"risk_level\": \"safe|low|medium|high|critical\",\n  \"reasoning\": \"brief explanation\",\n  \"destructive\": true/false,\n  \"reversible\": true/false\n}"
    
    local response=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$api_key" \
        -H "Content-Type: application/json" \
        -X POST \
        -d "$(jq -n --arg text "$prompt" '{contents:[{parts:[{text:$text}]}]}')" 2>/dev/null)
    
    local text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)
    local json=$(echo "$text" | grep -oP '\{[^}]*\}' | head -1)
    
    if [ -n "$json" ]; then
        local risk=$(echo "$json" | jq -r '.risk_level // "unknown"')
        local reasoning=$(echo "$json" | jq -r '.reasoning // "LLM analysis"')
        echo "$risk|$reasoning (LLM分析)"
    else
        echo "unknown|LLM 分析失败"
    fi
}

# 主分类函数
classify() {
    local command="$1"
    local context="${2:-}"
    local use_llm="${3:-true}"
    local start_time=$(date +%s%3N)
    
    echo "[Permission Classifier] 分析命令: $command"
    
    # 1. 检查缓存
    local cached=$(check_cache "$command")
    if [ -n "$cached" ]; then
        local risk=$(echo "$cached" | cut -d'|' -f1)
        local reason=$(echo "$cached" | cut -d'|' -f2-)
        echo "[Cache] 风险等级: $risk"
        echo "$risk|$reason (缓存)"
        return
    fi
    
    # 2. 规则分类
    local rule_result=$(classify_by_rules "$command")
    local rule_risk=$(echo "$rule_result" | cut -d'|' -f1)
    local rule_reason=$(echo "$rule_result" | cut -d'|' -f2-)
    
    # 如果是明确的 critical 或 safe，直接返回
    if [ "$rule_risk" = "critical" ] || [ "$rule_risk" = "safe" ]; then
        echo "[Rules] 风险等级: $rule_risk"
        cache_result "$command" "$rule_risk" "$rule_reason"
        echo "$rule_result"
        return
    fi
    
    # 3. LLM 分析（可选）
    if [ "$use_llm" = "true" ] && [ "$rule_risk" = "medium" ] || [ "$rule_risk" = "unknown" ]; then
        echo "[LLM] 进行深度分析..."
        local llm_result=$(llm_classify "$command" "$context")
        local llm_risk=$(echo "$llm_result" | cut -d'|' -f1)
        local llm_reason=$(echo "$llm_result" | cut -d'|' -f2-)
        
        if [ "$llm_risk" != "unknown" ]; then
            cache_result "$command" "$llm_risk" "$llm_reason"
            echo "$llm_result"
            return
        fi
    fi
    
    # 4. 返回规则结果
    cache_result "$command" "$rule_risk" "$rule_reason"
    echo "$rule_result"
}

# 获取风险配置
get_risk_config() {
    local level="$1"
    jq -r ".risk_levels.$level" "$CONFIG_FILE" 2>/dev/null
}

# 显示风险等级颜色
show_risk_color() {
    local level="$1"
    case "$level" in
        "safe")
            echo -e "${GREEN}✅ SAFE${NC}"
            ;;
        "low")
            echo -e "${BLUE}ℹ️ LOW${NC}"
            ;;
        "medium")
            echo -e "${YELLOW}⚠️ MEDIUM${NC}"
            ;;
        "high")
            echo -e "${ORANGE}🔶 HIGH${NC}"
            ;;
        "critical")
            echo -e "${RED}🚨 CRITICAL${NC}"
            ;;
        *)
            echo "$level"
            ;;
    esac
}

# 请求用户确认
request_confirmation() {
    local risk_level="$1"
    local command="$2"
    local reasoning="$3"
    
    local config=$(get_risk_config "$risk_level")
    local message=$(echo "$config" | jq -r '.confirmation_message // "请确认此操作"')
    local requires_reason=$(echo "$config" | jq -r '.requires_reason // false')
    
    echo ""
    echo "========================================"
    show_risk_color "$risk_level"
    echo "命令: $command"
    echo "原因: $reasoning"
    echo ""
    echo "$message"
    echo "========================================"
    echo ""
    echo "确认执行? (yes/no): "
    read confirm
    
    if [ "$confirm" = "yes" ] || [ "$confirm" = "y" ]; then
        if [ "$requires_reason" = "true" ]; then
            echo "请输入执行原因: "
            read reason
            echo "$reason"
        fi
        return 0
    else
        return 1
    fi
}

# 审计日志
log_decision() {
    local command="$1"
    local risk_level="$2"
    local reasoning="$3"
    local auto_executed="$4"
    local user_confirmed="$5"
    local user_reason="${6:-}"
    
    sqlite3 "$PERMISSION_DIR/audit.db" << EOF
INSERT INTO permission_decisions (command, risk_level, reasoning, auto_executed, user_confirmed, user_reason)
VALUES ('$(echo "$command" | sed "s/'/''/g")', '$risk_level', '$(echo "$reasoning" | sed "s/'/''/g")', $auto_executed, $user_confirmed, '$(echo "$user_reason" | sed "s/'/''/g")');
EOF
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$risk_level] $command" >> "$AUDIT_LOG"
}

# 测试分类器
test_classifier() {
    echo "=== Permission Classifier 测试 ==="
    echo ""
    
    local test_commands=(
        "ls -la"
        "cat ~/.bashrc"
        "rm -rf /tmp/test"
        "cp file1 file2"
        "git clone https://github.com/test/repo"
        "npm install express"
        "rm -rf /"
        "dd if=/dev/zero of=/dev/sda"
    )
    
    for cmd in "${test_commands[@]}"; do
        echo ""
        echo "测试命令: $cmd"
        local result=$(classify "$cmd" "" "false")
        local risk=$(echo "$result" | cut -d'|' -f1)
        local reason=$(echo "$result" | cut -d'|' -f2-)
        
        echo -n "风险等级: "
        show_risk_color "$risk"
        echo "分析: $reason"
    done
}

# 显示审计日志
show_audit_log() {
    local lines="${1:-20}"
    
    echo "=== 权限决策审计日志 (最近 $lines 条) ==="
    sqlite3 "$PERMISSION_DIR/audit.db" << EOF
SELECT strftime('%Y-%m-%d %H:%M', timestamp) as time, 
       risk_level, 
       substr(command, 1, 50) as cmd,
       CASE WHEN auto_executed = 1 THEN '自动' ELSE '确认' END as exec_type
FROM permission_decisions
ORDER BY timestamp DESC
LIMIT $lines;
EOF
}

# 统计信息
show_stats() {
    echo "=== Permission Classifier 统计 ==="
    echo ""
    
    echo "风险等级分布:"
    sqlite3 "$PERMISSION_DIR/audit.db" << EOF
SELECT risk_level, COUNT(*) as count 
FROM permission_decisions 
GROUP BY risk_level;
EOF
    
    echo ""
    echo "执行方式统计:"
    sqlite3 "$PERMISSION_DIR/audit.db" << EOF
SELECT 
    CASE WHEN auto_executed = 1 THEN '自动执行' ELSE '用户确认' END as type,
    COUNT(*) as count
FROM permission_decisions
GROUP BY auto_executed;
EOF
    
    echo ""
    echo "缓存命中率:"
    sqlite3 "$PERMISSION_DIR/audit.db" << EOF
SELECT SUM(hit_count) as total_hits, COUNT(*) as cached_commands
FROM risk_cache;
EOF
}

# 主入口
main() {
    case "$1" in
        "init")
            init_permission_classifier
            ;;
        "classify")
            classify "$2" "$3" "$4"
            ;;
        "test")
            test_classifier
            ;;
        "audit")
            show_audit_log "$2"
            ;;
        "stats")
            show_stats
            ;;
        *)
            echo "Permission Classifier - 基于 Claude Code 架构"
            echo ""
            echo "用法:"
            echo "  $0 init                          - 初始化"
            echo "  $0 classify '<command>' [context] [use_llm] - 分类命令风险"
            echo "  $0 test                          - 测试分类器"
            echo "  $0 audit [lines]                 - 查看审计日志"
            echo "  $0 stats                         - 统计信息"
            ;;
    esac
}

main "$@"
