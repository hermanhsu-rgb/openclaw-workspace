#!/bin/bash
# agent_loop_v4.sh - Agent Loop + State Machine + Hooks 完整版

source ~/.openclaw/.env 2>/dev/null
source ~/.openclaw/agent_loop/state_machine.sh 2>/dev/null
source ~/.openclaw/agent_loop/hooks.sh 2>/dev/null

AGENT_LOOP_DIR="/root/.openclaw/agent_loop"
VERSION="4.0.0"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}[Agent Loop V4 v${VERSION}]${NC}"
echo "基于 Claude Code: State Machine + 20+ Event Hooks"
echo ""

# Agent Loop V4 主函数
agent_loop_v4() {
    local user_request="$1"
    local session_id="${2:-}"
    local max_steps="${3:-10}"
    
    # 1. 创建或恢复会话
    if [ -z "$session_id" ]; then
        # 触发: before_session_start
        if trig_event "before_session_start" "new" "$user_request"; then
            : # 继续执行
        else
            echo -e "${RED}❌ 会话被钩子取消${NC}"
            return 1
        fi
        
        session_id=$(create_session "" "{\"request\": \"$user_request\"}")
        echo -e "${BLUE}[Session]${NC} 新建会话: $session_id"
        transition "$session_id" "PENDING" "start" > /dev/null
    else
        echo -e "${BLUE}[Session]${NC} 恢复会话: $session_id"
        trig_event "before_session_start" "$session_id" "$user_request" > /dev/null
    fi
    
    # 2. 状态转换前触发钩子
    local current_state=$(get_current_state "$session_id")
    if [ "$current_state" = "PENDING" ]; then
        if ! trig_event "before_state_transition" "$session_id" "$current_state" "RUNNING"; then
            echo -e "${YELLOW}⚠️ 状态转换被钩子拦截${NC}"
            return 1
        fi
    fi
    
    # 3. 开始执行
    transition "$session_id" "RUNNING" "execute" > /dev/null
    trig_event "after_state_transition" "$session_id" "$current_state" "RUNNING" "1" > /dev/null
    
    echo -e "${GREEN}[Agent Loop V4]${NC} 开始处理: $user_request"
    echo "追踪 ID: $session_id"
    echo "----------------------------------------"
    
    # 4. 保存检查点
    save_checkpoint "$session_id" "init" > /dev/null
    trig_event "on_checkpoint_save" "$session_id" "init" "0" > /dev/null
    
    # 5. Agent Loop 执行
    local step=0
    local status="running"
    
    while [ $step -lt $max_steps ] && [ "$status" = "running" ]; do
        step=$((step + 1))
        echo -e "${YELLOW}Step $step:${NC}"
        
        current_state=$(get_current_state "$session_id")
        
        case "$current_state" in
            "RUNNING")
                # 决策下一步
                local decision=$(decide_next_step_v4 "$user_request" "$step")
                local action=$(echo "$decision" | cut -d'|' -f1)
                local details=$(echo "$decision" | cut -d'|' -f2-)
                
                case "$action" in
                    "TOOL")
                        local tool_name=$(echo "$details" | cut -d'|' -f1)
                        local tool_args=$(echo "$details" | cut -d'|' -f2-)
                        
                        echo "🔧 执行工具: $tool_name"
                        
                        # 触发: before_tool_call
                        if ! trig_event "before_tool_call" "$session_id" "$tool_name" "$tool_args"; then
                            echo -e "${YELLOW}⚠️ 工具调用被钩子取消${NC}"
                            continue
                        fi
                        
                        # 模拟工具执行
                        local start_time=$(date +%s%3N)
                        sleep 0.3
                        local result="{\"status\": \"success\", \"data\": \"result of $tool_name\"}"
                        local end_time=$(date +%s%3N)
                        local duration=$((end_time - start_time))
                        
                        # 触发: after_tool_result
                        trig_event "after_tool_result" "$session_id" "$tool_name" "$result" "$duration" > /dev/null
                        
                        # 每 3 步保存检查点
                        if [ $((step % 3)) -eq 0 ]; then
                            save_checkpoint "$session_id" "step-$step" > /dev/null
                            trig_event "on_checkpoint_save" "$session_id" "step-$step" "$step" > /dev/null
                            echo "💾 检查点已保存"
                        fi
                        
                        # 记录指标
                        trig_event "on_metric_record" "$session_id" "tool_execution" "$duration" "{\"tool\": \"$tool_name\"}" > /dev/null
                        ;;
                        
                    "ASK")
                        echo "❓ 需要确认: $details"
                        
                        # 触发: on_permission_request
                        if ! trig_event "on_permission_request" "$session_id" "user_confirmation" "$details"; then
                            echo -e "${YELLOW}⚠️ 权限请求被钩子拒绝${NC}"
                            transition "$session_id" "CANCELLED" "cancel" > /dev/null
                            status="cancelled"
                            break
                        fi
                        
                        transition "$session_id" "WAITING" "wait" > /dev/null
                        status="waiting"
                        break
                        ;;
                        
                    "DONE")
                        echo -e "${GREEN}✅ 任务完成${NC}"
                        transition "$session_id" "COMPLETED" "complete" > /dev/null
                        trig_event "after_session_end" "$session_id" "COMPLETED" "$(($(date +%s%3N) - start_time))" > /dev/null
                        status="completed"
                        break
                        ;;
                        
                    "ERROR")
                        echo -e "${RED}❌ 执行错误${NC}"
                        trig_event "on_error" "$session_id" "EXECUTION_ERROR" "Step $step failed" "{\"step\": $step}" > /dev/null
                        
                        # 检查是否需要重试
                        local retry_count=$(sqlite3 "$STATE_DB" "SELECT retry_count FROM state_sessions WHERE session_id = '$session_id';")
                        if [ "$retry_count" -lt 3 ]; then
                            echo "🔄 自动重试 ($((retry_count + 1))/3)..."
                            transition "$session_id" "RETRYING" "retry" > /dev/null
                            trig_event "on_retry" "$session_id" "$retry_count" "3" > /dev/null
                            sleep 1
                            transition "$session_id" "RUNNING" "retry_execute" > /dev/null
                        else
                            transition "$session_id" "ERROR" "fail" > /dev/null
                            status="error"
                        fi
                        break
                        ;;
                esac
                ;;
                
            "PAUSED")
                echo -e "${YELLOW}⏸️ 会话已暂停${NC}"
                status="paused"
                break
                ;;
                
            "CANCELLED")
                echo -e "${YELLOW}❌ 会话已取消${NC}"
                status="cancelled"
                break
                ;;
        esac
    done
    
    # 达到最大步数
    if [ $step -ge $max_steps ] && [ "$status" = "running" ]; then
        echo -e "${YELLOW}⚠️ 达到最大步骤数，暂停执行${NC}"
        
        # 触发: before_compaction
        trig_event "before_compaction" "$session_id" "$step" "$max_steps" > /dev/null
        
        pause_session "$session_id" > /dev/null
        status="paused"
    fi
    
    echo "----------------------------------------"
    echo -e "${GREEN}[Agent Loop V4]${NC} 最终状态: $status"
    echo "会话 ID: $session_id"
    echo ""
    
    # 显示操作提示
    case "$status" in
        "waiting")
            echo "⏸️ 等待用户输入，可用操作:"
            echo "  恢复: ~/.openclaw/agent_loop/agent_loop_v4.sh resume $session_id"
            echo "  取消: ~/.openclaw/agent_loop/agent_loop_v4.sh cancel $session_id"
            ;;
        "paused")
            echo "⏸️ 会话已暂停，可用操作:"
            echo "  恢复: ~/.openclaw/agent_loop/agent_loop_v4.sh resume $session_id"
            ;;
        "error")
            echo "❌ 执行出错，可用操作:"
            echo "  查看日志: ~/.openclaw/agent_loop/hooks/logs/errors.log"
            ;;
    esac
}

# V4 决策函数
decide_next_step_v4() {
    local request="$1"
    local step="$2"
    
    if [ $step -eq 1 ]; then
        echo "TOOL|init|{\"action\": \"initialize\"}"
    elif [ $step -eq 5 ]; then
        echo "ASK|是否需要继续执行下一步？"
    elif [ $step -eq 8 ]; then
        echo "ERROR|模拟错误测试重试机制"
    elif [ $step -ge 10 ]; then
        echo "DONE|任务已完成"
    else
        echo "TOOL|step_$step|{\"step\": $step}"
    fi
}

# 恢复会话
resume_v4() {
    local session_id="$1"
    echo -e "${GREEN}[Agent Loop V4]${NC} 恢复会话: $session_id"
    agent_loop_v4 "" "$session_id"
}

# 取消会话
cancel_v4() {
    local session_id="$1"
    echo -e "${YELLOW}[Agent Loop V4]${NC} 取消会话: $session_id"
    
    # 触发: on_user_interrupt
    trig_event "on_user_interrupt" "$session_id" "user_cancel" > /dev/null
    
    cancel_session "$session_id"
}

# 主入口
main() {
    # 确保所有组件已初始化
    [ ! -f "$AGENT_LOOP_DIR/state_machine/states.db" ] && init_state_machine
    [ ! -f "$AGENT_LOOP_DIR/hooks/hooks.db" ] && init_hooks_system
    
    case "$1" in
        "run")
            agent_loop_v4 "$2" "" "$3"
            ;;
        "resume")
            resume_v4 "$2"
            ;;
        "cancel")
            cancel_v4 "$2"
            ;;
        "test")
            echo "=== Agent Loop V4 测试 ==="
            echo ""
            echo "测试 1: 正常执行任务"
            agent_loop_v4 "测试任务 - 完整 Hook 流程" "" 12
            ;;
        "status")
            echo "Agent Loop V4 v${VERSION}"
            echo ""
            echo "组件状态:"
            [ -f "$AGENT_LOOP_DIR/state_machine/states.db" ] && echo "  ✅ State Machine"
            [ -f "$AGENT_LOOP_DIR/hooks/hooks.db" ] && echo "  ✅ Event Hooks"
            ;;
        *)
            echo "Agent Loop V4 v${VERSION}"
            echo "基于 Claude Code: State Machine + 20+ Event Hooks"
            echo ""
            echo "用法:"
            echo "  $0 run '<请求>' [max_steps]  - 运行 Agent Loop"
            echo "  $0 resume <session_id>       - 恢复会话"
            echo "  $0 cancel <session_id>       - 取消会话"
            echo "  $0 test                      - 测试功能"
            echo "  $0 status                    - 查看状态"
            ;;
    esac
}

main "$@"
