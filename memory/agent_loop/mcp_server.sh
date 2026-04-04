#!/bin/bash
# mcp_server.sh - OpenClaw MCP 服务器实现
# 支持 Claude Desktop 和 Cursor 调用

source ~/.openclaw/.env 2>/dev/null

# MCP 协议处理
handle_initialize() {
    cat << 'EOF'
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"serverInfo":{"name":"openclaw-mcp","version":"1.0.0"}}}
EOF
}

handle_tools_list() {
    cat << 'EOF'
{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"search","description":"Search the web using Tavily","inputSchema":{"type":"object","properties":{"query":{"type":"string"},"max_results":{"type":"integer","default":5}},"required":["query"]}},{"name":"execute_bash","description":"Execute a bash command safely","inputSchema":{"type":"object","properties":{"command":{"type":"string"},"timeout":{"type":"integer","default":30}},"required":["command"]}},{"name":"read_file","description":"Read a file","inputSchema":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}}]}}
EOF
}

handle_tool_call() {
    local name=$(echo "$1" | jq -r '.params.name')
    local arguments=$(echo "$1" | jq -r '.params.arguments')
    
    case "$name" in
        "search")
            local query=$(echo "$arguments" | jq -r '.query')
            local max_results=$(echo "$arguments" | jq -r '.max_results // 5')
            
            if [ -n "$TAVILY_API_KEY" ]; then
                local result=$(curl -s -X POST "https://api.tavily.com/search" \
                    -H "Content-Type: application/json" \
                    -d "{\"api_key\": \"$TAVILY_API_KEY\", \"query\": \"$query\", \"max_results\": $max_results}" 2>/dev/null)
                
                echo '{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":'"$(echo "$result" | jq -Rs .)"'}]}}'
            else
                echo '{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"TAVILY_API_KEY not set"}],"isError":true}}'
            fi
            ;;
            
        "execute_bash")
            local command=$(echo "$arguments" | jq -r '.command')
            local timeout=$(echo "$arguments" | jq -r '.timeout // 30')
            
            # 安全限制：只允许白名单命令
            if echo "$command" | grep -qE "^(ls|cat|echo|grep|head|tail|wc|date|pwd|whoami|df|free|ps|top)($| )"; then
                local result=$(timeout $timeout bash -c "$command" 2>&1 || echo "Command failed or timed out")
                echo '{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":'"$(echo "$result" | jq -Rs .)"'}]}}'
            else
                echo '{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"Command not in whitelist"}],"isError":true}}'
            fi
            ;;
            
        "read_file")
            local filepath=$(echo "$arguments" | jq -r '.path')
            
            # 安全检查：限制在 home 目录
            if echo "$filepath" | grep -qE "^/root/|^/home/|^\./|^\.\./"; then
                if [ -f "$filepath" ]; then
                    local content=$(head -100 "$filepath" 2>/dev/null || echo "Cannot read file")
                    echo '{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":'"$(echo "$content" | jq -Rs .)"'}]}}'
                else
                    echo '{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"File not found"}],"isError":true}}'
                fi
            else
                echo '{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"Path not allowed"}],"isError":true}}'
            fi
            ;;
            
        *)
            echo '{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"Unknown tool"}],"isError":true}}'
            ;;
    esac
}

# 主循环 - 读取 stdin 的 JSON-RPC 请求
main() {
    while IFS= read -r line; do
        # 解析请求
        local method=$(echo "$line" | jq -r '.method // empty')
        
        case "$method" in
            "initialize")
                handle_initialize
                ;;
            "tools/list")
                handle_tools_list
                ;;
            "tools/call")
                handle_tool_call "$line"
                ;;
            *)
                echo '{"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"}}'
                ;;
        esac
    done
}

main "$@"
