#!/bin/bash
# agent_loop.sh - OpenClaw Agent Loop 实现
# 基于 Claude Code 泄露源码架构

AGENT_LOOP_DIR="/root/.openclaw/agent_loop"
LOG_FILE="$AGENT_LOOP_DIR/agent_loop.log"
MAX_ITERATIONS=10
CONTEXT_WINDOW_LIMIT=8000

# 初始化
echo "[$(date)] ===== Agent Loop 启动 =====" >> "$LOG_FILE"

# 创建必要目录
mkdir -p "$AGENT_LOOP_DIR"/{sessions,context,tools}

# Agent Loop 主函数
run_agent_loop() {
    local user_input="$1"
    local session_id="${2:-$(date +%s)}"
    local iteration=0
    local intent="continue"
    local context_file="$AGENT_LOOP_DIR/sessions/${session_id}.json"
    
    # 初始化上下文
    cat > "$context_file" << EOF
{
    "session_id": "$session_id",
    "start_time": "$(date -Iseconds)",
    "user_input": $(echo "$user_input" | jq -Rs .),
    "iterations": [],
    "status": "running"
}
EOF
    
    echo "[$(date)] Session: $session_id - 用户输入: $user_input" >> "$LOG_FILE"
    
    while [ "$intent" != "done" ] && [ $iteration -lt $MAX_ITERATIONS ]; do
        iteration=$((iteration + 1))
        echo "[$(date)] Iteration $iteration" >> "$LOG_FILE"
        
        # 1. 构建上下文
        local context=$(build_context "$context_file" "$iteration")
        
        # 2. 决定下一步（调用 LLM）
        local decision=$(decide_next_step "$context" "$user_input")
        intent=$(echo "$decision" | jq -r '.intent')
        
        echo "[$(date)] Decision: $intent" >> "$LOG_FILE"
        
        # 记录决策
        jq --arg iter "$iteration" \
           --argjson decision "$decision" \
           '.iterations += [{"iteration": ($iter | tonumber), "decision": $decision}]' \
           "$context_file" > "${context_file}.tmp" && mv "${context_file}.tmp" "$context_file"
        
        # 3. 根据意图执行
        case "$intent" in
            "tool_call")
                local tool_name=$(echo "$decision" | jq -r '.tool.name')
                local tool_args=$(echo "$decision" | jq -r '.tool.arguments')
                
                echo "[$(date)] 执行工具: $tool_name" >> "$LOG_FILE"
                
                # 执行工具
                local result=$(execute_tool "$tool_name" "$tool_args")
                
                # 压缩结果（避免上下文爆炸）
                result=$(compact_result "$result" "$tool_name")
                
                # 记录结果
                jq --arg iter "$iteration" \
                   --argjson result "$result" \
                   '.iterations[-1].result = $result' \
                   "$context_file" > "${context_file}.tmp" && mv "${context_file}.tmp" "$context_file"
                ;;
                
            "ask_user")
                local question=$(echo "$decision" | jq -r '.question')
                echo "[$(date)] 需要用户确认: $question" >> "$LOG_FILE"
                
                # 发送消息给用户
                send_to_user "🤔 $question"
                
                # 等待用户回复（通过文件标记）
                touch "$AGENT_LOOP_DIR/waiting_for_user_${session_id}"
                jq '.status = "waiting"' "$context_file" > "${context_file}.tmp" && mv "${context_file}.tmp" "$context_file"
                return 0
                ;;
                
            "done")
                local final_answer=$(echo "$decision" | jq -r '.answer')
                echo "[$(date)] 完成: $final_answer" >> "$LOG_FILE"
                
                jq --arg answer "$final_answer" \
                   '.status = "completed" | .final_answer = $answer' \
                   "$context_file" > "${context_file}.tmp" && mv "${context_file}.tmp" "$context_file"
                
                # 发送最终答案给用户
                send_to_user "✅ $final_answer"
                return 0
                ;;
                
            "error")
                local error_msg=$(echo "$decision" | jq -r '.error')
                echo "[$(date)] 错误: $error_msg" >> "$LOG_FILE"
                send_to_user "❌ 出错了: $error_msg"
                jq '.status = "error"' "$context_file" > "${context_file}.tmp" && mv "${context_file}.tmp" "$context_file"
                return 1
                ;;
        esac
    done
    
    # 达到最大迭代次数
    if [ $iteration -ge $MAX_ITERATIONS ]; then
        echo "[$(date)] 达到最大迭代次数 ($MAX_ITERATIONS)" >> "$LOG_FILE"
        send_to_user "⚠️ 任务执行步数过多，请简化请求或分批执行"
        jq '.status = "timeout"' "$context_file" > "${context_file}.tmp" && mv "${context_file}.tmp" "$context_file"
        return 1
    fi
}

# 构建上下文
build_context() {
    local context_file="$1"
    local current_iter="$2"
    
    # 读取历史
    local history=$(jq -r '.iterations | map("\(.iteration): \(.decision.intent) - \(.decision.tool.name // "N/A")") | join("\n")' "$context_file" 2>/dev/null || echo "")
    
    # 如果上下文太长，进行摘要
    local history_len=${#history}
    if [ $history_len -gt $CONTEXT_WINDOW_LIMIT ]; then
        history=$(echo "$history" | tail -c $CONTEXT_WINDOW_LIMIT)
        history="...(前面内容已摘要)...\n$history"
    fi
    
    echo "$history"
}

# 决定下一步（模拟 LLM 决策）
decide_next_step() {
    local context="$1"
    local user_input="$2"
    
    # 这里应该调用实际的 LLM API
    # 现在用简单的规则模拟
    
    # 检查是否需要使用工具
    if echo "$user_input" | grep -qiE "(搜索|查|找|weather|天气|温度)"; then
        cat << EOF
{
    "intent": "tool_call",
    "tool": {
        "name": "tavily-search",
        "arguments": {"query": "$user_input"}
    },
    "reasoning": "用户需要搜索信息"
}
EOF
    elif echo "$user_input" | grep -qiE "(删除|移除|del|rm)"; then
        cat << EOF
{
    "intent": "ask_user",
    "question": "您要进行删除操作，请确认是否继续？"
}
EOF
    else
        cat << EOF
{
    "intent": "done",
    "answer": "已处理您的请求: $user_input"
}
EOF
    fi
}

# 执行工具
execute_tool() {
    local tool_name="$1"
    local tool_args="$2"
    
    echo "[$(date)] 执行: $tool_name" >> "$LOG_FILE"
    
    case "$tool_name" in
        "tavily-search")
            local query=$(echo "$tool_args" | jq -r '.query // empty')
            if [ -n "$query" ] && [ -n "$TAVILY_API_KEY" ]; then
                curl -s -X POST "https://api.tavily.com/search" \
                    -H "Content-Type: application/json" \
                    -d "{\"api_key\": \"$TAVILY_API_KEY\", \"query\": \"$query\", \"max_results\": 3}" \
                    2>/dev/null | jq -c '.results | map({title, url})'
            else
                echo '{"error": "TAVILY_API_KEY not set"}'
            fi
            ;;
        "file-read")
            local path=$(echo "$tool_args" | jq -r '.path // empty')
            if [ -f "$path" ]; then
                head -50 "$path" | jq -Rs .
            else
                echo '{"error": "File not found"}'
            fi
            ;;
        *)
            echo "{\"error\": \"Unknown tool: $tool_name\"}"
            ;;
    esac
}

# 压缩结果（防止上下文爆炸）
compact_result() {
    local result="$1"
    local tool_name="$2"
    local max_length=2000
    
    # 只对特定工具进行压缩
    case "$tool_name" in
        "tavily-search"|"web-search")
            # 搜索结果压缩：只保留标题和URL
            result=$(echo "$result" | jq -c 'map({title, url})')
            ;;
        "file-read")
            # 文件读取压缩：限制长度
            local len=${#result}
            if [ $len -gt $max_length ]; then
                result="$(echo "$result" | head -c $max_length)... (已截断)"
            fi
            ;;
    esac
    
    echo "$result"
}

# 发送消息给用户
send_to_user() {
    local message="$1"
    echo "[$(date)] 发送给用户: $message" >> "$LOG_FILE"
    # 实际实现：通过 OpenClaw message 工具发送
    echo "$message"
}

# 恢复等待中的会话
resume_session() {
    local session_id="$1"
    local user_response="$2"
    local context_file="$AGENT_LOOP_DIR/sessions/${session_id}.json"
    
    # 移除等待标记
    rm -f "$AGENT_LOOP_DIR/waiting_for_user_${session_id}"
    
    # 记录用户回复
    jq --arg response "$user_response" \
       '.user_response = $response | .status = "running"' \
       "$context_file" > "${context_file}.tmp" && mv "${context_file}.tmp" "$context_file"
    
    # 继续循环
    local user_input=$(jq -r '.user_input' "$context_file")
    run_agent_loop "$user_input" "$session_id"
}

# 主入口
main() {
    case "$1" in
        "run")
            run_agent_loop "$2"
            ;;
        "resume")
            resume_session "$2" "$3"
            ;;
        "status")
            ls -la "$AGENT_LOOP_DIR/sessions/" 2>/dev/null
            ;;
        *)
            echo "用法: $0 run '<用户输入>' | resume <session_id> '<用户回复>' | status"
            ;;
    esac
}

main "$@"
