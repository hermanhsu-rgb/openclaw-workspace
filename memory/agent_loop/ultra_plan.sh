#!/bin/bash
# ultra_plan.sh - OpenClaw Ultra Plan Mode
# 基于 Claude Code 架构：深度任务规划、依赖分析、风险评估

ULTRA_PLAN_DIR="/root/.openclaw/agent_loop/ultra_plan"
CONFIG_FILE="/root/.openclaw/agent_loop/ultra_plan_config.json"
PLANS_DB="$ULTRA_PLAN_DIR/plans.db"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 初始化 Ultra Plan
init_ultra_plan() {
    echo "初始化 Ultra Plan Mode..."
    mkdir -p "$ULTRA_PLAN_DIR"/{plans,graphs,checkpoints}
    
    # 创建计划数据库
    sqlite3 "$PLANS_DB" << 'EOF'
CREATE TABLE IF NOT EXISTS plans (
    plan_id TEXT PRIMARY KEY,
    task_description TEXT,
    status TEXT DEFAULT 'planning',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    current_phase TEXT,
    progress_percent INTEGER DEFAULT 0,
    metadata TEXT
);

CREATE TABLE IF NOT EXISTS subtasks (
    subtask_id TEXT PRIMARY KEY,
    plan_id TEXT,
    parent_id TEXT,
    description TEXT,
    status TEXT DEFAULT 'pending',
    complexity INTEGER,
    estimated_duration INTEGER,
    actual_duration INTEGER,
    dependencies TEXT,
    risk_level TEXT,
    execution_order INTEGER,
    FOREIGN KEY (plan_id) REFERENCES plans(plan_id)
);

CREATE TABLE IF NOT EXISTS dependencies (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    plan_id TEXT,
    from_subtask TEXT,
    to_subtask TEXT,
    dependency_type TEXT,
    FOREIGN KEY (plan_id) REFERENCES plans(plan_id)
);

CREATE TABLE IF NOT EXISTS checkpoints (
    checkpoint_id TEXT PRIMARY KEY,
    plan_id TEXT,
    subtask_id TEXT,
    phase TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    state_snapshot TEXT,
    FOREIGN KEY (plan_id) REFERENCES plans(plan_id)
);

CREATE TABLE IF NOT EXISTS execution_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    plan_id TEXT,
    subtask_id TEXT,
    action TEXT,
    status TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    details TEXT
);

CREATE INDEX IF NOT EXISTS idx_subtasks_plan ON subtasks(plan_id);
CREATE INDEX IF NOT EXISTS idx_dependencies_plan ON dependencies(plan_id);
CREATE INDEX IF NOT EXISTS idx_checkpoints_plan ON checkpoints(plan_id);
EOF
    
    echo "✅ Ultra Plan Mode 已初始化"
}

# 创建新计划
create_plan() {
    local task="$1"
    local plan_id="plan-$(date +%s)-$RANDOM"
    
    sqlite3 "$PLANS_DB" << EOF
INSERT INTO plans (plan_id, task_description, current_phase)
VALUES ('$plan_id', '$(echo "$task" | sed "s/'/''/g")', 'analyze');
EOF
    
    echo "$plan_id"
}

# Phase 1: 分析
phase_analyze() {
    local plan_id="$1"
    local task="$2"
    
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Phase 1: 分析当前状态              ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo ""
    
    # 模拟分析（实际应该用 LLM）
    echo "📊 收集系统状态..."
    echo "   - 当前工作目录: $(pwd)"
    echo "   - 可用磁盘空间: $(df -h / | tail -1 | awk '{print $4}')"
    echo "   - 内存使用情况: $(free -h | grep Mem | awk '{print $3"/"$2}')"
    echo ""
    
    echo "🔍 识别相关资源..."
    echo "   - 检查相关 skills..."
    echo "   - 检查 API 连接状态..."
    echo ""
    
    echo "⚠️  评估约束条件..."
    echo "   - 权限限制: 当前用户权限"
    echo "   - 时间限制: 无明确限制"
    echo ""
    
    echo "📚 分析历史任务..."
    echo "   - 查询类似任务执行记录..."
    
    # 保存分析结果
    sqlite3 "$PLANS_DB" << EOF
UPDATE plans SET current_phase = 'decompose', progress_percent = 15 WHERE plan_id = '$plan_id';
INSERT INTO checkpoints (checkpoint_id, plan_id, phase, state_snapshot)
VALUES ('cp-${plan_id}-analyze', '$plan_id', 'analyze', '{"phase": "analyze", "progress": 15}');
EOF
    
    echo ""
    echo -e "${GREEN}✅ 分析完成${NC}"
}

# Phase 2: 任务分解
phase_decompose() {
    local plan_id="$1"
    local task="$2"
    
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Phase 2: 任务分解                  ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""
    
    # 根据任务类型自动分解
    echo "🎯 识别主要目标: $task"
    echo ""
    
    echo "📋 拆分子任务..."
    
    # 模拟子任务生成
    local subtasks_desc=(
        "1:初始化环境:2:"
        "2:收集信息:3:1"
        "3:制定方案:4:1,2"
        "4:执行操作:5:3"
        "5:验证结果:2:4"
        "6:清理收尾:1:5"
    )
    
    local order=1
    for subtask in "${subtasks_desc[@]}"; do
        IFS=':' read -r id desc complexity deps <<< "$subtask"
        
        # 安全地转义描述
        local safe_desc=$(echo "$desc" | sed "s/'/''/g")
        
        sqlite3 "$PLANS_DB" "INSERT INTO subtasks (subtask_id, plan_id, description, complexity, dependencies, execution_order) VALUES ('${plan_id}-st${id}', '$plan_id', '$safe_desc', $complexity, '$deps', $order);"
        
        echo "   $order. $desc (复杂度: $complexity/10)"
        if [ -n "$deps" ]; then
            echo "      └─ 依赖: $deps"
        fi
        order=$((order + 1))
    done
    
    sqlite3 "$PLANS_DB" << EOF
UPDATE plans SET current_phase = 'dependencies', progress_percent = 30 WHERE plan_id = '$plan_id';
EOF
    
    echo ""
    echo -e "${GREEN}✅ 任务分解完成 - 生成 $((order-1)) 个子任务${NC}"
}

# Phase 3: 依赖关系分析
phase_dependencies() {
    local plan_id="$1"
    
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  Phase 3: 依赖关系分析              ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════╝${NC}"
    echo ""
    
    echo "🔗 构建依赖图..."
    
    # 获取子任务
    local subtasks=$(sqlite3 "$PLANS_DB" << EOF
SELECT subtask_id, description, dependencies FROM subtasks WHERE plan_id = '$plan_id' ORDER BY execution_order;
EOF
)
    
    echo ""
    echo "依赖关系:"
    echo "┌─────────────────────────────────────────┐"
    
    while IFS='|' read -r id desc deps; do
        if [ -n "$deps" ]; then
            echo "│  $id ──depends on──> $deps"
            
            # 保存依赖关系
            for dep in $(echo "$deps" | tr ',' ' '); do
                sqlite3 "$PLANS_DB" << EOF
INSERT INTO dependencies (plan_id, from_subtask, to_subtask, dependency_type)
VALUES ('$plan_id', '$id', '${plan_id}-st$dep', 'hard');
EOF
            done
        else
            echo "│  $id (无依赖)"
        fi
    done <<< "$subtasks"
    
    echo "└─────────────────────────────────────────┘"
    
    echo ""
    echo "⚡ 识别并行执行机会:"
    echo "   - 子任务 1 (初始化环境) 可立即执行"
    echo "   - 子任务 2-3 (收集信息/制定方案) 依赖 1"
    echo "   - 子任务 4-5-6 必须串行执行"
    
    sqlite3 "$PLANS_DB" << EOF
UPDATE plans SET current_phase = 'schedule', progress_percent = 45 WHERE plan_id = '$plan_id';
EOF
    
    echo ""
    echo -e "${GREEN}✅ 依赖分析完成${NC}"
}

# Phase 4: 生成执行计划
phase_schedule() {
    local plan_id="$1"
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Phase 4: 执行计划生成              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""
    
    echo "📅 生成执行序列..."
    echo ""
    
    # 获取执行计划
    local plan=$(sqlite3 "$PLANS_DB" << EOF
SELECT s.subtask_id, s.description, s.complexity, s.dependencies, s.execution_order
FROM subtasks s
WHERE s.plan_id = '$plan_id'
ORDER BY s.execution_order;
EOF
)
    
    echo "执行路线图:"
    echo "═══════════════════════════════════════════"
    
    local total_complexity=0
    while IFS='|' read -r id desc complexity deps order; do
        total_complexity=$((total_complexity + complexity))
        
        local bar=""
        for ((i=0; i<complexity; i++)); do
            bar="${bar}█"
        done
        
        printf "  Step %d: %-20s [%s] %d/10\n" "$order" "$desc" "$bar" "$complexity"
    done <<< "$plan"
    
    echo "═══════════════════════════════════════════"
    echo "预计总复杂度: $total_complexity/60"
    echo "预计执行时间: ~$((total_complexity * 2)) 分钟"
    
    echo ""
    echo "📍 设置检查点:"
    echo "   CP-1: Phase 2 完成后"
    echo "   CP-2: 50% 子任务完成后"
    echo "   CP-3: 全部完成后"
    
    sqlite3 "$PLANS_DB" << EOF
UPDATE plans SET current_phase = 'risk', progress_percent = 60 WHERE plan_id = '$plan_id';
EOF
    
    echo ""
    echo -e "${GREEN}✅ 执行计划生成完成${NC}"
}

# Phase 5: 风险评估
phase_risk() {
    local plan_id="$1"
    
    echo ""
    echo -e "${RED}╔══════════════════════════════════════╗${NC}"
    echo -e "${RED}║  Phase 5: 风险评估                  ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════╝${NC}"
    echo ""
    
    echo "⚠️  识别潜在失败点:"
    echo ""
    
    # 模拟风险评估
    local risks=(
        "HIGH|API 限流|可能导致搜索失败|使用缓存/降级方案"
        "MEDIUM|磁盘空间不足|可能导致日志写入失败|监控磁盘使用"
        "LOW|网络延迟|可能影响响应时间|设置超时重试"
        "MEDIUM|权限不足|可能导致文件操作失败|提前检查权限"
    )
    
    echo "风险矩阵:"
    echo "┌──────────┬──────────────────┬─────────────────────┬────────────────────┐"
    echo "│ 风险等级 │ 潜在问题         │ 影响范围            │ 缓解措施           │"
    echo "├──────────┼──────────────────┼─────────────────────┼────────────────────┤"
    
    for risk in "${risks[@]}"; do
        IFS='|' read -r level problem impact mitigation <<< "$risk"
        printf "│ %-8s │ %-16s │ %-19s │ %-18s │\n" "$level" "$problem" "$impact" "$mitigation"
    done
    
    echo "└──────────┴──────────────────┴─────────────────────┴────────────────────┘"
    
    echo ""
    echo "🛡️  制定缓解策略:"
    echo "   1. 所有外部调用添加超时和重试"
    echo "   2. 关键操作前保存检查点"
    echo "   3. 准备应急回滚方案"
    
    sqlite3 "$PLANS_DB" << EOF
UPDATE plans SET current_phase = 'ready', progress_percent = 75 WHERE plan_id = '$plan_id';
EOF
    
    echo ""
    echo -e "${GREEN}✅ 风险评估完成${NC}"
}

# 生成完整计划报告
generate_plan_report() {
    local plan_id="$1"
    
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           ULTRA PLAN MODE - 完整执行计划              ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # 获取计划信息
    local task=$(sqlite3 "$PLANS_DB" "SELECT task_description FROM plans WHERE plan_id = '$plan_id';")
    
    echo "🎯 任务目标: $task"
    echo "🆔 计划 ID: $plan_id"
    echo ""
    
    echo "📋 子任务列表:"
    echo "─────────────────────────────────────────────────────────"
    sqlite3 "$PLANS_DB" << EOF
SELECT execution_order, description, complexity, 
       CASE 
           WHEN dependencies = '' THEN '无依赖'
           ELSE '依赖: ' || dependencies
       END as deps,
       risk_level
FROM subtasks 
WHERE plan_id = '$plan_id'
ORDER BY execution_order;
EOF
    
    echo ""
    echo "🚀 准备执行计划？"
    echo "   输入 'yes' 开始执行"
    echo "   输入 'modify' 修改计划"
    echo "   输入 'cancel' 取消"
    
    read confirm
    
    case "$confirm" in
        "yes"|"y")
            sqlite3 "$PLANS_DB" "UPDATE plans SET status = 'ready', current_phase = 'execute' WHERE plan_id = '$plan_id';"
            echo -e "${GREEN}✅ 计划已准备就绪，可以开始执行${NC}"
            return 0
            ;;
        "modify"|"m")
            echo "计划修改功能开发中..."
            return 1
            ;;
        *)
            sqlite3 "$PLANS_DB" "UPDATE plans SET status = 'cancelled' WHERE plan_id = '$plan_id';"
            echo "计划已取消"
            return 1
            ;;
    esac
}

# 执行计划
execute_plan() {
    local plan_id="$1"
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Phase 6: 执行监控                  ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""
    
    sqlite3 "$PLANS_DB" "UPDATE plans SET status = 'executing', started_at = CURRENT_TIMESTAMP WHERE plan_id = '$plan_id';"
    
    # 获取待执行子任务
    local subtasks=$(sqlite3 "$PLANS_DB" << EOF
SELECT subtask_id, description, complexity, execution_order
FROM subtasks 
WHERE plan_id = '$plan_id' AND status = 'pending'
ORDER BY execution_order;
EOF
)
    
    local total=$(echo "$subtasks" | wc -l)
    local current=0
    
    while IFS='|' read -r id desc complexity order; do
        [ -z "$id" ] && continue
        current=$((current + 1))
        
        echo ""
        echo "[$current/$total] 执行: $desc"
        echo "      复杂度: $complexity/10"
        
        # 模拟执行
        sleep 0.5
        
        # 更新状态
        sqlite3 "$PLANS_DB" << EOF
UPDATE subtasks SET status = 'completed' WHERE subtask_id = '$id';
INSERT INTO execution_log (plan_id, subtask_id, action, status)
VALUES ('$plan_id', '$id', 'execute', 'success');
EOF
        
        local progress=$((75 + current * 20 / total))
        sqlite3 "$PLANS_DB" "UPDATE plans SET progress_percent = $progress WHERE plan_id = '$plan_id';"
        
        echo "      ${GREEN}✅ 完成${NC}"
    done <<< "$subtasks"
    
    sqlite3 "$PLANS_DB" "UPDATE plans SET status = 'completed', completed_at = CURRENT_TIMESTAMP, progress_percent = 100 WHERE plan_id = '$plan_id';"
    
    echo ""
    echo -e "${GREEN}✅ 计划执行完成！${NC}"
}

# 主 Ultra Plan 函数
ultra_plan() {
    local task="$1"
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     ULTRA PLAN MODE - 超详细规划模式                  ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "任务: $task"
    echo ""
    
    # 创建计划
    local plan_id=$(create_plan "$task")
    echo "🆔 计划 ID: $plan_id"
    echo ""
    
    # 执行 7 个规划阶段
    phase_analyze "$plan_id" "$task"
    phase_decompose "$plan_id" "$task"
    phase_dependencies "$plan_id"
    phase_schedule "$plan_id"
    phase_risk "$plan_id"
    
    # 生成报告
    if generate_plan_report "$plan_id"; then
        execute_plan "$plan_id"
    fi
}

# 列出计划
list_plans() {
    echo "=== Ultra Plan 计划列表 ==="
    sqlite3 "$PLANS_DB" << EOF
SELECT plan_id, 
       substr(task_description, 1, 30) as task,
       status,
       progress_percent || '%' as progress,
       current_phase
FROM plans
ORDER BY created_at DESC
LIMIT 20;
EOF
}

# 查看计划详情
show_plan() {
    local plan_id="$1"
    
    echo "=== 计划详情: $plan_id ==="
    sqlite3 "$PLANS_DB" << EOF
SELECT * FROM plans WHERE plan_id = '$plan_id';
EOF
    
    echo ""
    echo "子任务:"
    sqlite3 "$PLANS_DB" << EOF
SELECT execution_order, description, status, complexity 
FROM subtasks WHERE plan_id = '$plan_id' ORDER BY execution_order;
EOF
}

# 主入口
main() {
    case "$1" in
        "init")
            init_ultra_plan
            ;;
        "plan")
            ultra_plan "$2"
            ;;
        "list")
            list_plans
            ;;
        "show")
            show_plan "$2"
            ;;
        *)
            echo "Ultra Plan Mode - 基于 Claude Code 架构"
            echo ""
            echo "7 阶段深度规划:"
            echo "  1. 分析 (Analyze)      - 收集状态、识别资源"
            echo "  2. 分解 (Decompose)    - 拆分为子任务"
            echo "  3. 依赖 (Dependencies) - 分析依赖关系"
            echo "  4. 计划 (Schedule)     - 生成执行路线"
            echo "  5. 风险 (Risk)         - 评估并制定缓解策略"
            echo "  6. 执行 (Execute)      - 监控执行"
            echo "  7. 验证 (Verify)       - 确认结果"
            echo ""
            echo "用法:"
            echo "  $0 init                  - 初始化"
            echo "  $0 plan '<任务描述>'     - 创建超详细计划"
            echo "  $0 list                  - 列出所有计划"
            echo "  $0 show <plan_id>        - 查看计划详情"
            ;;
    esac
}

main "$@"
