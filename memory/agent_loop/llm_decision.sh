#!/bin/bash
# llm_decision.sh - LLM 决策引擎
# 用真实 LLM 替代规则引擎

source ~/.openclaw/.env 2>/dev/null

# LLM 决策函数
llm_decide_next_step() {
    local context="$1"
    local user_input="$2"
    local session_history="$3"
    
    # 构建 prompt
    local prompt=$(cat <<EOF
You are an AI agent decision engine. Based on the user's request and context, decide the next action.

User Request: $user_input

Context:
$context

Session History:
$session_history

Available Tools:
- tavily-search: Search the web for information
- file-read: Read a file from the system
- bash: Execute bash commands for multi-step operations
- ask-user: Ask user for confirmation or clarification
- done: Complete the task with final answer

Respond with a JSON object:
{
    "intent": "tool_call|ask_user|done|error",
    "tool": {"name": "tool-name", "arguments": {}},
    "question": "question to ask user (if intent is ask_user)",
    "answer": "final answer (if intent is done)",
    "reasoning": "why you chose this action"
}

Response:
EOF
)
    
    # 调用 Gemini API
    local api_key="${GEMINI_API_KEY:-}"
    if [ -z "$api_key" ]; then
        echo '{"intent":"error","error":"GEMINI_API_KEY not set"}'
        return 1
    fi
    
    local response=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$api_key" \
        -H "Content-Type: application/json" \
        -X POST \
        -d "$(jq -n --arg text "$prompt" '{contents:[{parts:[{text:$text}]}]}')" 2>/dev/null)
    
    # 解析响应
    local text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)
    
    # 提取 JSON
    local json=$(echo "$text" | grep -oP '\{.*\}' | head -1)
    
    if [ -n "$json" ]; then
        echo "$json"
    else
        # 降级到规则引擎
        echo '{"intent":"done","answer":"LLM决策失败，使用默认响应","reasoning":"fallback"}'
    fi
}

# 流式 LLM 调用（用于复杂任务）
llm_stream_decision() {
    local prompt="$1"
    local api_key="${GEMINI_API_KEY:-}"
    
    curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent?key=$api_key" \
        -H "Content-Type: application/json" \
        -X POST \
        -d "$(jq -n --arg text "$prompt" '{contents:[{parts:[{text:$text}]}]}')" 2>/dev/null | \
        jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null
}

# 工具参数生成
llm_generate_tool_args() {
    local tool_name="$1"
    local user_input="$2"
    local context="$3"
    
    local prompt=$(cat <<EOF
Generate arguments for tool "$tool_name" based on user input.

User Input: $user_input
Context: $context

Tool: $tool_name

Respond with a JSON object containing the tool arguments.
For tavily-search: {"query": "search query", "max_results": 5}
For file-read: {"path": "/path/to/file"}
For bash: {"command": "bash command to execute"}

Response:
EOF
)
    
    local api_key="${GEMINI_API_KEY:-}"
    local response=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$api_key" \
        -H "Content-Type: application/json" \
        -X POST \
        -d "$(jq -n --arg text "$prompt" '{contents:[{parts:[{text:$text}]}]}')" 2>/dev/null)
    
    echo "$response" | jq -r '.candidates[0].content.parts[0].text // "{}"' | grep -oP '\{.*\}' | head -1
}

# 测试函数
test_llm_decision() {
    echo "=== 测试 LLM 决策 ==="
    
    local test_input="搜索最新的 AI Agent 框架"
    echo "输入: $test_input"
    
    local result=$(llm_decide_next_step "" "$test_input" "")
    echo "LLM 决策结果:"
    echo "$result" | jq . 2>/dev/null || echo "$result"
}

# 主入口
main() {
    case "$1" in
        "test")
            test_llm_decision
            ;;
        "decide")
            llm_decide_next_step "$2" "$3" "$4"
            ;;
        *)
            echo "用法: $0 test | decide <context> <input> <history>"
            ;;
    esac
}

main "$@"
