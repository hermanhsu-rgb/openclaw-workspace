#!/bin/bash
# agent_loop_v3.sh - Agent Loop Pro + State Machine 集成版

source ~/.openclaw/.env 2>/dev/null
source ~/.openclaw/agent_loop/state_machine.sh 2>/dev/null

AGENT_LOOP_DIR="/root/.openclaw/agent_loop"
VERSION="3.0.0"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}[Agent Loop V3 v${VERSION}]${NC}"
echo "基于 Claude Code 泄露源码架构 + State Machine"
echo ""

# Agent Loop V3 主函数
agent_loop_v3() {
    local user_request="$1"
    local session_id="${2:-}"
    local max_steps="${3:-10}"
    
    # 1. 创建或恢复会话
    if [ -z "$session_id" ]; then
        session_id=$(create_session "" "{\"request\": \"$user_request\"}")
        echo -e "${BLUE}[Session]${NC} 新建会话: $session_id"
        
        # 初始状态转换: IDLE → PENDING
        transition "$session_id" "PENDING" "start" "{\"request\": \"$user_request\"}" > /dev/null
    else
        echo -e "${BLUE}[Session]${NC} 恢复会话: $session_id"
        local current_state=$(get_current_state "$session_id")
        echo "当前状态: $current_state"
        
        if [ "$current_state" = "PAUSED" ] || [ "$current_state" = "WAITING" ]; then
            resume_session "$session_id" > /dev/null
        fi
    fi
    
    # 2. 开始执行: PENDING → RUNNING
    transition "$session_id" "RUNNING" "execute" > /dev/null
    
    echo -e "${GREEN}[Agent Loop V3]${NC} 开始处理: $user_request"
    echo "追踪 ID: $session_id"
    echo "----------------------------------------"
    
    # 3. 保存初始检查点
    save_checkpoint "$session_id" "step-0-init" > /dev/null
    
    # 4. Agent Loop 执行
    local step=0
    local status="running"
    
    while [ $step -lt $max_steps ] && [ "$status" = "running" ]; do
        step=$((step + 1))
        echo -e "${YELLOW}Step $step:${NC}"
        
        # 获取当前状态
        local current_state=$(get_current_state "$session_id")
        
        case "$current_state" in
            "RUNNING")
                # 执行实际任务
                local decision=$(decide_next_step "$user_request" "$step")
                local action=$(echo "$decision" | cut -d'|' -f1)
                local details=$(echo "$decision" | cut -d'|' -f2-)
                
                case "$action" in
                    "TOOL")
                        echo "🔧 执行工具: $details"
                        # 模拟工具执行
                        sleep 0.5
                        
                        # 每 3 步保存检查点
                        if [ $((step % 3)) -eq 0 ]; then
                            save_checkpoint "$session_id" "step-$step" > /dev/null
                            echo "💾 检查点已保存"
                        fi
                        ;;
                        
                    "ASK")
                        echo "❓ 需要确认: $details"
                        transition "$session_id" "WAITING" "wait" > /dev/null
                        status="waiting"
                        break
                        ;;
                        
                    "DONE")
                        echo -e "${GREEN}✅ 任务完成${NC}"
                        transition "$session_id" "COMPLETED" "complete" > /dev/null
                        status="completed"
                        break
                        ;;
                        
                    "ERROR")
                        echo -e "${RED}❌ 执行错误${NC}"
                        transition "$session_id" "ERROR" "fail" > /dev/null
                        status="error"
                        break
                        ;;
                esac
                ;;
                
            "PAUSED")
                echo -e "${YELLOW}⏸️ 会话已暂停，等待恢复${NC}"
                status="paused"
                break
                ;;
                
            "CANCELLED")
                echo -e "${YELLOW}❌ 会话已取消${NC}"
                status="cancelled"
                break
                ;;
                
            *)
                echo -e "${YELLOW}⚠️ 未知状态: $current_state${NC}"
                status="unknown"
                break
                ;;
        esac
        
        # 模拟处理时间
        sleep 0.3
    done
    
    # 5. 检查是否达到最大步数
    if [ $step -ge $max_steps ] && [ "$status" = "running" ]; then
        echo -e "${YELLOW}⚠️ 达到最大步骤数 ($max_steps)，暂停执行${NC}"
        pause_session "$session_id" > /dev/null
        status="paused"
    fi
    
    echo "----------------------------------------"
    echo -e "${GREEN}[Agent Loop V3]${NC} 最终状态: $status"
    echo "会话 ID: $session_id"
    echo ""
    echo "可用操作:"
    echo "  恢复: ~/.openclaw/agent_loop/agent_loop_v3.sh resume $session_id"
    echo "  取消: ~/.openclaw/agent_loop/agent_loop_v3.sh cancel $session_id"
    echo "  状态: ~/.openclaw/agent_loop/state_machine.sh stats $session_id"
}

# 决策函数（简化版）
decide_next_step() {
    local request="$1"
    local step="$2"
    
    # 模拟决策逻辑
    if [ $step -eq 1 ]; then
        echo "TOOL|初始化任务"
    elif [ $step -eq 5 ]; then
        echo "ASK|是否需要继续执行下一步？"
    elif [ $step -ge 8 ]; then
        echo "DONE|任务已完成"
    else
        echo "TOOL|执行步骤 $step"
    fi
}

# 恢复会话
resume_v3() {
    local session_id="$1"
    echo -e "${GREEN}[Agent Loop V3]${NC} 恢复会话: $session_id"
    agent_loop_v3 "" "$session_id"
}

# 取消会话
cancel_v3() {
    local session_id="$1"
    echo -e "${YELLOW}[Agent Loop V3]${NC} 取消会话: $session_id"
    cancel_session "$session_id"
}

# 主入口
main() {
    # 确保状态机已初始化
    if [ ! -f "$AGENT_LOOP_DIR/state_machine/states.db" ]; then
        init_state_machine
    fi
    
    case "$1" in
        "run")
            agent_loop_v3 "$2" "" "$3"
            ;;
        "resume")
            resume_v3 "$2"
            ;;
        "cancel")
            cancel_v3 "$2"
            ;;
        "test")
            echo "=== Agent Loop V3 测试 ==="
            echo ""
            echo "测试 1: 正常执行任务"
            agent_loop_v3 "测试任务示例" "" 5
            ;;
        *)
            echo "Agent Loop V3 v${VERSION}"
            echo "基于 Claude Code 泄露源码架构 + State Machine"
            echo ""
            echo "用法:"
            echo "  $0 run '<请求>' [max_steps]  - 运行 Agent Loop"
            echo "  $0 resume <session_id>       - 恢复会话"
            echo "  $0 cancel <session_id>       - 取消会话"
            echo "  $0 test                      - 测试功能"
            ;;
    esac
}

main "$@"
