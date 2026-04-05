#!/bin/bash
# agent_loop_morning_push.sh - 晨间推送（Tavily 搜索版）

set -e

source ~/.openclaw/.env 2>/dev/null || true

TODAY=$(date "+%Y-%m-%d")
YESTERDAY=$(date -d "yesterday" "+%Y-%m-%d" 2>/dev/null || date -v-1d "+%Y-%m-%d" 2>/dev/null || echo "$TODAY")
HOUR=$(date +%H)
MIN=$(date +%M)

LOG_FILE="/root/.openclaw/agent_loop/morning_push.log"
LOCK_FILE="/tmp/morning_push.lock"

# 防止重复运行
if [ -f "$LOCK_FILE" ]; then
    PID=$(cat "$LOCK_FILE" 2>/dev/null)
    if ps -p "$PID" > /dev/null 2>&1; then
        echo "[$(date)] 推送已在运行 (PID: $PID)，跳过" >> "$LOG_FILE"
        exit 0
    fi
fi
echo $$ > "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

echo "[$(date)] ===== Agent Loop 晨间推送 =====" >> "$LOG_FILE"

# 根据时间决定推送内容
case "$HOUR:$MIN" in
    "08:00"|"08:01")
        TYPE="dental"
        ;;
    "09:00"|"09:01")
        TYPE="weather"
        ;;
    *)
        echo "[$(date)] 不在推送时间段 ($HOUR:$MIN)，跳过" >> "$LOG_FILE"
        exit 0
        ;;
esac

echo "[$(date)] 推送类型: $TYPE" >> "$LOG_FILE"

# ========== 天气推送 ==========
if [ "$TYPE" = "weather" ]; then
    CITY="Shanghai"
    WEATHER=$(curl -s "wttr.in/${CITY}?format=%C|%t|%w|%h" 2>/dev/null || echo "")
    if [ -n "$WEATHER" ]; then
        CONDITION=$(echo "$WEATHER" | cut -d'|' -f1)
        TEMP=$(echo "$WEATHER" | cut -d'|' -f2)
        WIND=$(echo "$WEATHER" | cut -d'|' -f3)
        HUMID=$(echo "$WEATHER" | cut -d'|' -f4)
        
        MESSAGE="🌤️ 早安！今日天气 - $TODAY

📍 城市：${CITY}
🌡️ 温度：${TEMP}
☁️ 天气：${CONDITION}
💨 风速：${WIND}
💧 湿度：${HUMID}

祝您今天愉快！"
    else
        MESSAGE="🌤️ 天气服务暂时不可用"
    fi
    
    echo "$MESSAGE"
    echo "[$(date)] 天气推送完成" >> "$LOG_FILE"
    exit 0
fi

# ========== 牙科资讯推送（Tavily 搜索）==========
if [ "$TYPE" = "dental" ]; then
    echo "[$(date)] 开始 Tavily 搜索..." >> "$LOG_FILE"
    
    # 检查 Tavily API Key
    if [ -z "$TAVILY_API_KEY" ]; then
        echo "[$(date)] 错误: TAVILY_API_KEY 未设置" >> "$LOG_FILE"
        MESSAGE="🦷 数字化牙科资讯 - $TODAY

⚠️ Tavily API Key 未配置

请检查 ~/.openclaw/.env 配置"
        echo "$MESSAGE"
        exit 1
    fi
    
    # 搜索过去24小时的牙科数字化资讯
    SEARCH_QUERIES=(
        "dental 3D printing innovation 2025"
        "intraoral scanner accuracy new study 2025"
        "AI dental crown design algorithm 2025"
        "CAD CAM dental materials new 2025"
    )
    
    RESULTS=""
    COUNT=0
    
    for QUERY in "${SEARCH_QUERIES[@]}"; do
        echo "[$(date)] 搜索: $QUERY" >> "$LOG_FILE"
        
        JSON_RESULT=$(curl -s -X POST "https://api.tavily.com/search" \
            -H "Content-Type: application/json" \
            -d "{
                \"api_key\": \"${TAVILY_API_KEY}\",
                \"query\": \"${QUERY}\",
                \"max_results\": 2,
                \"search_depth\": \"basic\",
                \"include_answer\": true,
                \"time_range\": \"day\"
            }" 2>/dev/null || echo "{}")
        
        # 解析结果
        if command -v python3 >/dev/null 2>&1; then
            TITLE=$(echo "$JSON_RESULT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'results' in data and len(data['results']) > 0:
        print(data['results'][0].get('title', 'No title')[:80])
except:
    print('')
" 2>/dev/null || echo "")
            
            CONTENT=$(echo "$JSON_RESULT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'results' in data and len(data['results']) > 0:
        print(data['results'][0].get('content', 'No content')[:200])
except:
    print('')
" 2>/dev/null || echo "")
            
            URL=$(echo "$JSON_RESULT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'results' in data and len(data['results']) > 0:
        print(data['results'][0].get('url', ''))
except:
    print('')
" 2>/dev/null || echo "")
        else
            # 基础 grep 提取（fallback）
            TITLE=$(echo "$JSON_RESULT" | grep -o '"title":"[^"]*"' | head -1 | cut -d'"' -f4 | cut -c1-80)
            CONTENT=$(echo "$JSON_RESULT" | grep -o '"content":"[^"]*"' | head -1 | cut -d'"' -f4 | cut -c1-200)
            URL=$(echo "$JSON_RESULT" | grep -o '"url":"[^"]*"' | head -1 | cut -d'"' -f4)
        fi
        
        if [ -n "$TITLE" ] && [ "$TITLE" != "No title" ]; then
            COUNT=$((COUNT + 1))
            RESULTS="${RESULTS}

${COUNT}️⃣ ${TITLE}
   ${CONTENT}
   🔗 ${URL}"        
        fi
        
        # 限制最多4条
        if [ $COUNT -ge 4 ]; then
            break
        fi
        
        # 避免请求过快
        sleep 0.5
    done
    
    if [ $COUNT -eq 0 ]; then
        MESSAGE="🦷 数字化牙科资讯 - $TODAY

📰 今日搜索暂时未返回新结果

💡 建议稍后重试或查看专业期刊"
    else
        MESSAGE="🦷 数字化牙科资讯 - $TODAY

📰 过去24小时最新动态（${COUNT}条）：${RESULTS}

💡 搜索来源: Tavily"
    fi
    
    echo "$MESSAGE"
    echo "[$(date)] 牙科资讯推送完成，获取 ${COUNT} 条结果" >> "$LOG_FILE"
fi

exit 0
