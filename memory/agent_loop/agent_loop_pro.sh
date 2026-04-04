#!/bin/bash
# agent_loop_pro.sh - 完整版 Agent Loop (5 项升级整合)
# 1. LLM 决策 + 2. 多 Agent Swarm + 3. 完整可观测性 + 4. microCompact + 5. MCP 兼容

source ~/.openclaw/.env 2>/dev/null

AGENT_LOOP_DIR="/root/.openclaw/agent_loop"
VERSION="2.0.0"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}[Agent Loop Pro v${VERSION}]${NC}"
echo "基于 Claude Code 泄露源码架构"
echo ""

# 初始化所有组件
init_all() {
    echo "初始化 Agent Loop Pro..."
    
    # 1. 可观测性
    [ -f "$AGENT_LOOP_DIR/observability.sh" ] && source "$AGENT_LOOP_DIR/observability.sh" && init_observability
    
    # 2. 压缩配置
    [ -f "$AGENT_LOOP_DIR/micro_compact.sh" ] && source "$AGENT_LOOP_DIR/micro_compact.sh" && init_compact_config
    
    # 3. Swarm 配置
    mkdir -p "$AGENT_LOOP_DIR/swarm"/{coordinator,researcher,infrastructure,content_creator,scheduler}
    
    echo "✅ 初始化完成"
}

# LLM 决策（升级 1）
llm_decide() {
    local prompt="$1"
    local api_key="${GEMINI_API_KEY:-}"
    
    if [ -z "$api_key" ]; then
        echo '{"intent":"error","error":"GEMINI_API_KEY not set"}'
        return 1
    fi
    
    local response=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$api_key" \
        -H "Content-Type: application/json" \
        -X POST \
        -d "$(jq -n --arg text "$prompt" '{contents:[{parts:[{text:$text}]}]}')" 2>/dev/null)
    
    echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty' | grep -oP '\{.*\}' | head -1
}

# 多 Agent Swarm 路由（升级 2）
route_to_agent() {
    local request="$1"
    
    # LLM 路由决策
    local route_prompt=$(cat <<EOF
Route this request to the appropriate agent:

Request: $request

Available agents:
- researcher: For search, information gathering, web queries
- infrastructure: For system management, cloud operations, updates
- content_creator: For writing, summarizing, content generation
- scheduler: For timing, reminders, scheduling tasks

Respond with JSON: {"agent": "agent_name", "reasoning": "why"}
EOF
)
    
    local route=$(llm_decide "$route_prompt")
    local agent=$(echo "$route" | jq -r '.agent // "researcher"')
    
    echo "$agent"
}

# 执行 Agent 任务
execute_agent() {
    local agent="$1"
    local task="$2"
    local trace_id="$3"
    
    # 记录 Span（升级 3）
    local span_id=$(record_span "$trace_id" "agent_$agent" "" "{\"task\": \"$task\"}" 2>/dev/null || echo "span-$RANDOM")
    
    echo -e "${BLUE}[Agent: $agent]${NC} $task"
    
    case "$agent" in
        "researcher")
            source ~/.openclaw/.env
            if [ -n "$TAVILY_API_KEY" ]; then
                local result=$(curl -s -X POST "https://api.tavily.com/search" \
                    -H "Content-Type: application/json" \
                    -d "{\"api_key\": \"$TAVILY_API_KEY\", \"query\": \"$task\", \"max_results\": 3}" 2>/dev/null)
                
                # 压缩结果（升级 4）
                source "$AGENT_LOOP_DIR/micro_compact.sh" 2>/dev/null
                result=$(compact_search_results "$result" 3)
                
                echo "$result"
            else
                echo '{"error": "TAVILY_API_KEY not set"}'
            fi
            ;;
            
        "infrastructure")
            echo "执行基础设施任务: $task"
            # 系统命令执行（带安全限制）
            ;;
            
        "content_creator")
            echo "生成内容: $task"
            # 调用 summarize 等 skills
            ;;
            
        "scheduler")
            echo "调度任务: $task"
            crontab -l | grep -E "(8:|9:|3:)" || echo "暂无相关定时任务"
            ;;
            
        *)
            echo "未知 Agent: $agent"
            ;;
    esac
    
    # 结束 Span
    end_span "$span_id" "completed" 2>/dev/null || true
}

# MCP 工具调用（升级 5）
call_mcp_tool() {
    local tool="$1"
    local args="$2"
    
    case "$tool" in
        "search")
            execute_agent "researcher" "$(echo "$args" | jq -r '.query')" ""
            ;;
        "execute_bash")
            local cmd=$(echo "$args" | jq -r '.command')
            timeout 30 bash -c "$cmd" 2>&1 || echo "Command failed"
            ;;
        "read_file")
            local path=$(echo "$args" | jq -r '.path')
            [ -f "$path" ] && head -50 "$path" || echo "File not found"
            ;;
        *)
            echo "Unknown MCP tool: $tool"
            ;;
    esac
}

# 主 Agent Loop
agent_loop_pro() {
    local user_request="$1"
    local max_steps="${2:-5}"
    
    # 开始追踪
    local trace_id=$(start_trace "session-$(date +%s)" "$user_request" 2>/dev/null || echo "trace-$RANDOM")
    
    echo -e "${GREEN}[Agent Loop Pro]${NC} 开始处理: $user_request"
    echo "追踪 ID: $trace_id"
    echo "----------------------------------------"
    
    # 路由到合适的 Agent
    local agent=$(route_to_agent "$user_request")
    echo -e "${YELLOW}路由到 Agent:${NC} $agent"
    echo ""
    
    # 执行 Agent 任务
    local step=0
    while [ $step -lt $max_steps ]; do
        step=$((step + 1))
        echo -e "${YELLOW}Step $step:${NC}"
        
        local result=$(execute_agent "$agent" "$user_request" "$trace_id")
        
        # 检查是否需要进一步操作
        if echo "$result" | jq -e '.results' > /dev/null 2>&1; then
            echo -e "${GREEN}✅ 获取结果:${NC}"
            echo "$result" | jq -r '.results[] | "- \(.title): \(.url)"' 2>/dev/null | head -5
            break
        elif echo "$result" | grep -q "error"; then
            echo -e "${RED}❌ 错误:${NC} $result"
            break
        fi
        
        sleep 0.5
    done
    
    # 结束追踪
    end_trace "$trace_id" "completed" "$result" 2>/dev/null || true
    
    echo "----------------------------------------"
    echo -e "${GREEN}[Agent Loop Pro]${NC} 完成"
    
    # 记录指标
    record_metric "agent_loop_steps" "$step" "{\"agent\": \"$agent\"}" 2>/dev/null || true
}

# 测试全部功能
test_all() {
    echo "=== Agent Loop Pro 测试 ==="
    echo ""
    
    echo "1. LLM 决策:"
    local decision=$(llm_decide 'Respond with JSON: {"test": "llm_works"}')
    echo "   结果: $decision"
    
    echo ""
    echo "2. 多 Agent Swarm:"
    local agent=$(route_to_agent "搜索最新技术")
    echo "   路由到: $agent"
    
    echo ""
    echo "3. 可观测性:"
    [ -f "$AGENT_LOOP_DIR/observability/traces.db" ] && echo "   ✅ 数据库已初始化"
    
    echo ""
    echo "4. microCompact:"
    [ -f "$AGENT_LOOP_DIR/compact_config.json" ] && echo "   ✅ 配置已初始化"
    
    echo ""
    echo "5. MCP 兼容:"
    [ -f "$AGENT_LOOP_DIR/mcp_server.sh" ] && echo "   ✅ MCP 服务器已配置"
    
    echo ""
    echo "=== 完整执行测试 ==="
    agent_loop_pro "搜索最新的 AI Agent 框架"
}

# 主入口
main() {
    case "$1" in
        "init")
            init_all
            ;;
        "run")
            agent_loop_pro "$2" "$3"
            ;;
        "test")
            test_all
            ;;
        "status")
            echo "Agent Loop Pro v${VERSION}"
            echo ""
            echo "组件状态:"
            [ -f "$AGENT_LOOP_DIR/llm_decision.sh" ] && echo "  ✅ LLM 决策"
            [ -f "$AGENT_LOOP_DIR/agent_swarm.sh" ] && echo "  ✅ 多 Agent Swarm"
            [ -f "$AGENT_LOOP_DIR/observability.sh" ] && echo "  ✅ 可观测性"
            [ -f "$AGENT_LOOP_DIR/micro_compact.sh" ] && echo "  ✅ microCompact"
            [ -f "$AGENT_LOOP_DIR/mcp_server.sh" ] && echo "  ✅ MCP 兼容"
            ;;
        *)
            echo "Agent Loop Pro v${VERSION}"
            echo ""
            echo "用法:"
            echo "  $0 init              - 初始化所有组件"
            echo "  $0 run '<请求>'      - 运行 Agent Loop"
            echo "  $0 test              - 测试所有功能"
            echo "  $0 status            - 查看状态"
            ;;
    esac
}

main "$@"
