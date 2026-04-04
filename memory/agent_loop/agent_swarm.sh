#!/bin/bash
# agent_swarm.sh - 多 Agent Swarm 管理器

SWARM_DIR="/root/.openclaw/agent_loop/swarm"
CONFIG_FILE="/root/.openclaw/agent_loop/swarm_config.json"

# 初始化 Swarm
init_swarm() {
    echo "初始化 Agent Swarm..."
    mkdir -p "$SWARM_DIR"/{coordinator,researcher,infrastructure,content_creator,scheduler}
    mkdir -p "$SWARM_DIR/shared_context"
    echo "✅ Swarm 目录结构已创建"
}

# 协调器 - 路由请求到合适的 Agent
coordinator() {
    local user_request="$1"
    
    echo "[Coordinator] 接收请求: $user_request"
    
    # 简单路由逻辑（实际应该用 LLM）
    if echo "$user_request" | grep -qiE "(搜索|查|找|search|weather|天气|资料)"; then
        echo "[Coordinator] → 分发给 Researcher"
        agent_researcher "$user_request"
    elif echo "$user_request" | grep -qiE "(服务器|腾讯|云|lighthouse|cos|update|升级|安装)"; then
        echo "[Coordinator] → 分发给 Infrastructure"
        agent_infrastructure "$user_request"
    elif echo "$user_request" | grep -qiE "(写|生成|总结|翻译|pdf|summarize)"; then
        echo "[Coordinator] → 分发给 Content Creator"
        agent_content_creator "$user_request"
    elif echo "$user_request" | grep -qiE "(定时|提醒|推送|schedule|cron)"; then
        echo "[Coordinator] → 分发给 Scheduler"
        agent_scheduler "$user_request"
    else
        echo "[Coordinator] → 使用默认 Agent (Researcher)"
        agent_researcher "$user_request"
    fi
}

# 研究员 Agent
agent_researcher() {
    local request="$1"
    echo "[Researcher] 执行: $request"
    
    # 使用搜索工具
    source ~/.openclaw/.env
    if [ -n "$TAVILY_API_KEY" ]; then
        echo "[Researcher] 使用 Tavily 搜索..."
        curl -s -X POST "https://api.tavily.com/search" \
            -H "Content-Type: application/json" \
            -d "{\"api_key\": \"$TAVILY_API_KEY\", \"query\": \"$request\", \"max_results\": 3}" \
            2>/dev/null | jq -r '.results[] | "- \(.title): \(.url)"' 2>/dev/null
    else
        echo "[Researcher] TAVILY_API_KEY 未设置"
    fi
}

# 系统管理员 Agent
agent_infrastructure() {
    local request="$1"
    echo "[Infrastructure] 执行: $request"
    
    # 执行系统命令
    if echo "$request" | grep -qiE "(状态|status|检查|check)"; then
        echo "[Infrastructure] 系统状态:"
        echo "- 磁盘: $(df -h / | tail -1 | awk '{print $5}')"
        echo "- 内存: $(free -h | grep Mem | awk '{print $3"/"$2}')"
        echo "- 负载: $(uptime | awk -F'load average:' '{print $2}')"
    else
        echo "[Infrastructure] 准备执行基础设施操作..."
    fi
}

# 内容创作者 Agent
agent_content_creator() {
    local request="$1"
    echo "[Content Creator] 执行: $request"
    
    # 使用 summarize skill
    echo "[Content Creator] 生成内容摘要..."
    # 实际调用 summarize skill
}

# 调度员 Agent
agent_scheduler() {
    local request="$1"
    echo "[Scheduler] 执行: $request"
    
    # 检查定时任务
    echo "[Scheduler] 当前定时任务:"
    crontab -l | grep -E "(8:|9:|3:)" || echo "暂无相关定时任务"
}

# Fork 模式 - 并行执行多个 Agent
fork_agents() {
    local task="$1"
    echo "[Swarm] Fork 模式: 并行执行多个 Agent"
    
    # 并行启动多个 Agent
    agent_researcher "$task" &
    agent_infrastructure "$task" &
    wait
    
    echo "[Swarm] 所有 Agent 执行完成"
}

# Teammate 模式 - 协作执行
teammate_agents() {
    local task="$1"
    echo "[Swarm] Teammate 模式: 协作执行"
    
    # Researcher 收集信息
    local result=$(agent_researcher "$task")
    echo "$result" > "$SWARM_DIR/shared_context/last_research.json"
    
    # Content Creator 基于结果生成内容
    agent_content_creator "基于以下资料生成摘要: $result"
}

# 显示 Swarm 状态
swarm_status() {
    echo "=== Agent Swarm 状态 ==="
    echo ""
    echo "可用 Agents:"
    jq -r '.agents | keys[] as $k | "  - \($k): \(.[$k].role)"' "$CONFIG_FILE" 2>/dev/null || echo "  (配置加载失败)"
    echo ""
    echo "执行模式:"
    echo "  - fork: 并行执行"
    echo "  - teammate: 协作执行"  
    echo "  - worktree: 隔离执行"
}

# 主入口
main() {
    case "$1" in
        "init")
            init_swarm
            ;;
        "coordinator"|"route")
            coordinator "$2"
            ;;
        "researcher")
            agent_researcher "$2"
            ;;
        "infrastructure"|"infra")
            agent_infrastructure "$2"
            ;;
        "content"|"creator")
            agent_content_creator "$2"
            ;;
        "scheduler")
            agent_scheduler "$2"
            ;;
        "fork")
            fork_agents "$2"
            ;;
        "teammate")
            teammate_agents "$2"
            ;;
        "status")
            swarm_status
            ;;
        *)
            echo "Agent Swarm 管理器"
            echo ""
            echo "用法:"
            echo "  $0 init                    - 初始化 Swarm"
            echo "  $0 coordinator '<请求>'     - 通过协调器路由"
            echo "  $0 researcher '<查询>'      - 研究员 Agent"
            echo "  $0 infrastructure '<任务>'  - 系统管理员 Agent"
            echo "  $0 content '<任务>'         - 内容创作者 Agent"
            echo "  $0 scheduler '<任务>'       - 调度员 Agent"
            echo "  $0 fork '<任务>'            - Fork 模式（并行）"
            echo "  $0 teammate '<任务>'        - Teammate 模式（协作）"
            echo "  $0 status                  - 查看状态"
            ;;
    esac
}

main "$@"
