#!/bin/bash
# openclaw_agent_loop.sh - OpenClaw 集成版 Agent Loop
# 在现有工作流基础上添加循环决策能力

AGENT_LOOP_VERSION="1.0.0"
AGENT_LOOP_DIR="/root/.openclaw/agent_loop"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Agent Loop 核心函数
agent_loop() {
    local user_request="$1"
    local max_steps="${2:-5}"
    local step=0
    local status="running"
    local context=""
    
    echo -e "${GREEN}[Agent Loop v${AGENT_LOOP_VERSION}]${NC} 开始处理: $user_request"
    echo "最大步骤数: $max_steps"
    echo "----------------------------------------"
    
    while [ $step -lt $max_steps ] && [ "$status" = "running" ]; do
        step=$((step + 1))
        echo -e "\n${YELLOW}Step $step:${NC}"
        
        # 分析当前状态，决定下一步
        local decision=$(analyze_and_decide "$user_request" "$context" "$step")
        local action=$(echo "$decision" | cut -d'|' -f1)
        local details=$(echo "$decision" | cut -d'|' -f2-)
        
        case "$action" in
            "TOOL")
                echo "🔧 执行工具: $details"
                local result=$(execute_tool_safe "$details")
                context="${context}\n[Step $step] 工具: $details\n结果: $result"
                echo "✅ 工具执行完成"
                ;;
                
            "ASK")
                echo "❓ 需要确认: $details"
                echo -e "${YELLOW}[等待用户确认]${NC}"
                # 实际场景中会发送消息给用户
                status="waiting"
                break
                ;;
                
            "BASH")
                echo "💻 执行脚本: $details"
                # 使用 bash 进行多步操作（Claude Code 最佳实践）
                local result=$(bash -c "$details" 2>&1)
                context="${context}\n[Step $step] Bash脚本执行完成"
                echo "✅ 脚本执行完成"
                ;;
                
            "DONE")
                echo -e "${GREEN}✅ 任务完成:${NC} $details"
                status="completed"
                break
                ;;
                
            "ERROR")
                echo -e "${RED}❌ 错误:${NC} $details"
                status="error"
                break
                ;;
        esac
        
        # 检查上下文长度，必要时压缩
        if [ ${#context} -gt 6000 ]; then
            context=$(compact_context "$context")
            echo "📦 上下文已压缩"
        fi
        
        sleep 0.5
    done
    
    if [ $step -ge $max_steps ]; then
        echo -e "${YELLOW}⚠️ 达到最大步骤数，任务可能需要人工继续${NC}"
    fi
    
    echo "----------------------------------------"
    echo -e "${GREEN}[Agent Loop]${NC} 最终状态: $status"
    
    return 0
}

# 分析和决策函数
analyze_and_decide() {
    local request="$1"
    local context="$2"
    local step="$3"
    
    # 简单的规则引擎（实际应该用 LLM）
    
    # Step 1: 搜索信息
    if [ $step -eq 1 ] && echo "$request" | grep -qiE "(搜索|查|找|search|weather|天气)"; then
        echo "TOOL|tavily-search|$request"
        return
    fi
    
    # Step 2: 如果需要系统操作
    if echo "$request" | grep -qiE "(更新|升级|update|install)"; then
        if [ $step -eq 1 ]; then
            echo "TOOL|tavily-search|how to $request"
        else
            echo "DONE|已找到相关信息，请查看搜索结果"
        fi
        return
    fi
    
    # 危险操作：需要确认
    if echo "$request" | grep -qiE "(删除|del|rm|drop|clean|卸载)"; then
        echo "ASK|检测到删除操作，请确认是否继续？"
        return
    fi
    
    # 多步文件操作：使用 bash 脚本
    if echo "$request" | grep -qiE "(批量处理|多个文件|批量|batch)"; then
        echo "BASH|for f in /path/to/files/*; do echo \"Processing: \$f\"; done"
        return
    fi
    
    # 简单查询：直接完成
    echo "DONE|已处理您的请求"
}

# 安全执行工具
execute_tool_safe() {
    local tool_spec="$1"
    local tool_name=$(echo "$tool_spec" | cut -d'|' -f1)
    local tool_query=$(echo "$tool_spec" | cut -d'|' -f2-)
    
    case "$tool_name" in
        "tavily-search")
            if [ -n "$TAVILY_API_KEY" ]; then
                curl -s -X POST "https://api.tavily.com/search" \
                    -H "Content-Type: application/json" \
                    -d "{\"api_key\": \"$TAVILY_API_KEY\", \"query\": \"$tool_query\", \"max_results\": 3}" \
                    2>/dev/null | jq -r '.results[] | "- \(.title): \(.url)"' 2>/dev/null || echo "搜索失败"
            else
                echo "TAVILY_API_KEY 未设置"
            fi
            ;;
            
        "file-read")
            if [ -f "$tool_query" ]; then
                head -20 "$tool_query" 2>/dev/null || echo "无法读取文件"
            else
                echo "文件不存在: $tool_query"
            fi
            ;;
            
        *)
            echo "未知工具: $tool_name"
            ;;
    esac
}

# 压缩上下文
compact_context() {
    local ctx="$1"
    # 保留最近的3步，其余摘要
    local steps=$(echo -e "$ctx" | grep -c "\[Step")
    if [ $steps -gt 3 ]; then
        echo "...(前面 $((steps-3)) 步已摘要)..."
        echo -e "$ctx" | grep "\[Step" | tail -3
    else
        echo "$ctx"
    fi
}

# 快捷命令
quick_commands() {
    case "$1" in
        "search")
            shift
            agent_loop "搜索: $@"
            ;;
        "update")
            shift
            agent_loop "更新: $@"
            ;;
        "status")
            echo "Agent Loop 状态:"
            echo "版本: $AGENT_LOOP_VERSION"
            echo "目录: $AGENT_LOOP_DIR"
            ls -la "$AGENT_LOOP_DIR/sessions/" 2>/dev/null | head -10
            ;;
        *)
            agent_loop "$@"
            ;;
    esac
}

# 主入口
main() {
    # 加载环境变量
    source ~/.openclaw/.env 2>/dev/null
    
    # 创建目录
    mkdir -p "$AGENT_LOOP_DIR/sessions"
    
    if [ $# -eq 0 ]; then
        echo "OpenClaw Agent Loop v${AGENT_LOOP_VERSION}"
        echo "基于 Claude Code 泄露源码架构"
        echo ""
        echo "用法:"
        echo "  $0 '<用户请求>'          - 运行 Agent Loop"
        echo "  $0 search '<查询>'        - 快速搜索"
        echo "  $0 update '<任务>'        - 快速更新"
        echo "  $0 status                 - 查看状态"
        echo ""
        echo "示例:"
        echo "  $0 '搜索 Claude Code 架构'"
        echo "  $0 '更新所有 skills'"
        return 0
    fi
    
    quick_commands "$@"
}

main "$@"
