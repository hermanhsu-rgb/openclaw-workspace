#!/bin/bash
# micro_compact.sh - Claude Code 风格的工具结果压缩

COMPACT_CONFIG='/root/.openclaw/agent_loop/compact_config.json'

# 可压缩工具列表（Claude Code 的 COMPACTABLE_TOOLS）
COMPACTABLE_TOOLS=(
    "tavily-search"
    "web-search"
    "github-search"
    "file-read"
    "file-list"
    "directory-list"
)

# 初始化配置
init_compact_config() {
    cat > "$COMPACT_CONFIG" << 'EOF'
{
  "compactable_tools": ["tavily-search", "web-search", "github-search", "file-read", "file-list"],
  "strategies": {
    "search": {
      "max_results": 5,
      "fields": ["title", "url"],
      "truncate_content": 200,
      "remove_duplicates": true
    },
    "file": {
      "max_lines": 50,
      "max_chars": 3000,
      "show_line_numbers": true,
      "ellipsis": "... (truncated)"
    },
    "json": {
      "max_depth": 3,
      "max_array_items": 10,
      "summarize_large_arrays": true
    }
  },
  "token_limits": {
    "warning": 4000,
    "critical": 6000,
    "max": 8000
  }
}
EOF
    echo "✅ 压缩配置已初始化"
}

# 检查工具是否可压缩
is_compactable() {
    local tool_name="$1"
    for tool in "${COMPACTABLE_TOOLS[@]}"; do
        if [ "$tool" = "$tool_name" ]; then
            return 0
        fi
    done
    return 1
}

# 搜索结果压缩
compact_search_results() {
    local result="$1"
    local max_results="${2:-5}"
    
    # 1. 限制结果数量
    # 2. 只保留关键字段
    # 3. 截断长内容
    echo "$result" | jq -c "
        if .results then
            {
                results: [.results[:$max_results] | 
                    {title, url, content: (.content[:200] + if (.content | length) > 200 then \"...\" else \"\" end)}
                ]
            }
        else
            .
        end
    " 2>/dev/null || echo "$result"
}

# 文件内容压缩
compact_file_content() {
    local content="$1"
    local max_lines="${2:-50}"
    
    # 1. 限制行数
    # 2. 添加行号
    # 3. 显示截断提示
    local line_count=$(echo "$content" | wc -l)
    
    if [ $line_count -gt $max_lines ]; then
        echo "$content" | head -n $max_lines | nl
        echo ""
        echo "... ($((line_count - max_lines)) lines truncated)"
    else
        echo "$content" | nl
    fi
}

# JSON 数据压缩
compact_json() {
    local json="$1"
    local max_depth="${2:-3}"
    local max_items="${3:-10}"
    
    # 递归压缩 JSON
    echo "$json" | jq -c "
        walk(
            if type == \"array\" and length > $max_items then
                .[:$max_items] + [\"...(\(length - $max_items) more items)\"]
            elif type == \"object\" then
                with_entries(if .value | type == \"string\" and length > 200 then
                    .value |= .[:200] + \"...\" 
                else
                    .
                end)
            else
                .
            end
        )
    " 2>/dev/null || echo "$json"
}

# 智能压缩 - 根据内容类型自动选择策略
smart_compact() {
    local result="$1"
    local tool_name="$2"
    
    # 检查 token 数量（粗略估计）
    local token_count=${#result}
    
    # 根据大小选择压缩强度
    if [ $token_count -gt 8000 ]; then
        echo "[Compressed: Original ${token_count} chars]"
        echo "$result" | head -c 4000
        echo "... ($((${token_count} - 4000)) chars truncated)"
    elif [ $token_count -gt 4000 ]; then
        # 中等压缩
        case "$tool_name" in
            "tavily-search"|"web-search")
                compact_search_results "$result" 3
                ;;
            "file-read")
                compact_file_content "$result" 30
                ;;
            *)
                compact_json "$result" 2 5
                ;;
        esac
    else
        # 小于阈值，轻微压缩或不压缩
        echo "$result"
    fi
}

# microCompact 主函数（Claude Code 风格）
micro_compact() {
    local result="$1"
    local tool_name="$2"
    
    # 检查是否可压缩
    if ! is_compactable "$tool_name"; then
        echo "$result"
        return
    fi
    
    # 执行压缩
    smart_compact "$result" "$tool_name"
}

# 统计压缩效果
compact_stats() {
    local original_size="$1"
    local compacted_size="$2"
    
    local saved=$((original_size - compacted_size))
    local ratio=$(echo "scale=2; $saved * 100 / $original_size" | bc 2>/dev/null || echo "N/A")
    
    echo "Compression stats:"
    echo "  Original: $original_size chars"
    echo "  Compacted: $compacted_size chars"
    echo "  Saved: $saved chars (${ratio}%)"
}

# 测试压缩
test_compact() {
    echo "=== 测试 microCompact ==="
    
    # 测试 1: 搜索结果
    local search_result='{"results":[{"title":"Test 1","url":"http://test1.com","content":"This is a very long content that should be truncated because it exceeds the limit and we need to save tokens"},{"title":"Test 2","url":"http://test2.com","content":"Short content"},{"title":"Test 3","url":"http://test3.com","content":"Another long content that should be truncated for the same reason as the first one to demonstrate the compression"},{"title":"Test 4","url":"http://test4.com","content":"Content"},{"title":"Test 5","url":"http://test5.com","content":"Content"},{"title":"Test 6","url":"http://test6.com","content":"Should be removed"}]}'
    
    echo ""
    echo "Test 1: Search results"
    echo "Original size: ${#search_result}"
    local compacted=$(compact_search_results "$search_result" 3)
    echo "Compacted size: ${#compacted}"
    echo "Result: $compacted"
    
    # 测试 2: 文件内容
    echo ""
    echo "Test 2: File content (60 lines)"
    local file_content=$(seq 1 60 | while read i; do echo "Line $i: This is sample content for testing file compaction"; done)
    echo "Original lines: $(echo "$file_content" | wc -l)"
    local compacted_file=$(compact_file_content "$file_content" 20)
    echo "Compacted:"
    echo "$compacted_file"
}

# 主入口
main() {
    case "$1" in
        "init")
            init_compact_config
            ;;
        "compact")
            micro_compact "$2" "$3"
            ;;
        "test")
            test_compact
            ;;
        "stats")
            compact_stats "$2" "$3"
            ;;
        *)
            echo "microCompact - Claude Code 风格的工具结果压缩"
            echo ""
            echo "用法:"
            echo "  $0 init                          - 初始化配置"
            echo "  $0 compact '<result>' <tool>     - 压缩结果"
            echo "  $0 test                          - 测试压缩"
            echo "  $0 stats <original> <compacted>  - 统计压缩率"
            ;;
    esac
}

main "$@"
