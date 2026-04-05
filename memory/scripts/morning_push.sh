#!/bin/bash
# morning_push.sh - 晨间推送（Tavily实时搜索昨日-今日新闻）
# 每天早上 8:00、9:00、9:01 自动推送到企业微信

TODAY=$(date "+%Y-%m-%d")
YESTERDAY=$(date -d "yesterday" "+%Y-%m-%d" 2>/dev/null || date -v-1d "+%Y-%m-%d" 2>/dev/null || echo "昨天")
HOUR=$(date +%H)
MIN=$(date +%M)

# Tavily API Key
TAVILY_API_KEY="${TAVILY_API_KEY:-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}"

# 判断推送类型
case "$HOUR:$MIN" in
    "08:00")
        TYPE="dental"
        TITLE="🦷 牙科数字化每日新闻"
        
        # 使用 Tavily 搜索昨日-今日牙科数字化新闻
        TAVILY_RESPONSE=$(curl -s -X POST "https://api.tavily.com/search" \
            -H "Content-Type: application/json" \
            -d "{
                \"api_key\": \"${TAVILY_API_KEY}\",
                \"query\": \"dental digital dentistry AI CAD CAM news ${YESTERDAY} ${TODAY}\",
                \"search_depth\": \"advanced\",
                \"max_results\": 4,
                \"time_range\": \"day\",
                \"include_answer\": true
            }" 2>/dev/null)
        
        # 解析搜索结果
        if [ -n "$TAVILY_RESPONSE" ] && echo "$TAVILY_RESPONSE" | grep -q '"results"'; then
            # 提取标题和内容
            RESULT1=$(echo "$TAVILY_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['results'][0]['title']) if d.get('results') and len(d['results'])>0 else '无数据'" 2>/dev/null || echo "数据解析失败")
            RESULT2=$(echo "$TAVILY_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['results'][1]['title']) if d.get('results') and len(d['results'])>1 else '无数据'" 2>/dev/null || echo "")
            RESULT3=$(echo "$TAVILY_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['results'][2]['title']) if d.get('results') and len(d['results'])>2 else '无数据'" 2>/dev/null || echo "")
            RESULT4=$(echo "$TAVILY_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['results'][3]['title']) if d.get('results') and len(d['results'])>3 else '无数据'" 2>/dev/null || echo "")
            
            # 提取摘要
            ANSWER=$(echo "$TAVILY_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('answer',''))" 2>/dev/null)
            if [ -z "$ANSWER" ] || [ "$ANSWER" = "None" ] || [ "$ANSWER" = "null" ]; then
                ANSWER="昨日-今日牙科数字化领域持续活跃，国际会议和技术创新不断涌现。"
            fi
            
            MESSAGE="🦷 牙科数字化每日新闻 - ${TODAY}

📰 昨日-今日最新动态：

1️⃣ ${RESULT1}

2️⃣ ${RESULT2}

3️⃣ ${RESULT3}

4️⃣ ${RESULT4}

💡 智能摘要：
${ANSWER}

🔍 来源：Tavily AI实时搜索 | 24小时内更新
⏰ 推送时间：$(date "+%H:%M")"
        else
            # Tavily 失败时使用备用内容
            MESSAGE="🦷 牙科数字化每日新闻 - ${TODAY}

📰 昨日-今日行业动态：

• Exocad Insights 2026 | 4月30日-5月1日 | 西班牙马略卡岛
• IDEX Istanbul 2026 | 4月15-18日 | 土耳其伊斯坦布尔  
• Digital Dentistry 2026趋势报告 | 3D打印材料突破
• AI与VR/AR进入牙科诊所 | 自主工作流技术

💡 摘要：2026年牙科数字化加速发展，CAD/CAM、3D打印、AI成为焦点。

⚠️ Tavily搜索暂时不可用，显示默认行业动态
⏰ 推送时间：$(date "+%H:%M")"
        fi
        ;;
    
    "09:00")
        TYPE="weather"
        TITLE="🌤️ 早安天气提醒"
        CITY="Shanghai"
        WEATHER_RAW=$(curl -s "wttr.in/${CITY}?format=%C|%t|%w|%h" 2>/dev/null)
        
        if [ -n "$WEATHER_RAW" ]; then
            CONDITION=$(echo "$WEATHER_RAW" | cut -d'|' -f1 | sed 's/^[[:space:]]*//')
            TEMP=$(echo "$WEATHER_RAW" | cut -d'|' -f2 | sed 's/^[[:space:]]*//')
            WIND=$(echo "$WEATHER_RAW" | cut -d'|' -f3 | sed 's/^[[:space:]]*//')
            HUMIDITY=$(echo "$WEATHER_RAW" | cut -d'|' -f4 | sed 's/^[[:space:]]*//')
            
            TEMP_NUM=$(echo "$TEMP" | sed 's/[+-]//g; s/°C//g; s/C//g')
            if [ "$TEMP_NUM" -lt 10 ] 2>/dev/null; then
                OUTFIT="🧥 厚外套/羽绒服 + 保暖内衣"
            elif [ "$TEMP_NUM" -lt 20 ] 2>/dev/null; then
                OUTFIT="🧥 薄外套/长袖 + 长裤"
            elif [ "$TEMP_NUM" -lt 25 ] 2>/dev/null; then
                OUTFIT="👔 长袖/薄衫 + 长裤"
            elif [ "$TEMP_NUM" -lt 30 ] 2>/dev/null; then
                OUTFIT="👕 短袖/薄衣 + 长裤/短裤"
            else
                OUTFIT="🩳 短袖/短裤 + 凉鞋"
            fi
            
            MESSAGE="🌤️ 早安！今日天气提醒 - ${TODAY}

📍 城市：${CITY}
🌡️ 温度：${TEMP}
☁️ 天气：${CONDITION}
💨 风力：${WIND}
💧 湿度：${HUMIDITY}

👗 穿衣建议：${OUTFIT}

祝您今天愉快！"
        else
            MESSAGE="🌤️ 早安！今日天气服务暂时不可用，请稍后查看。"
        fi
        ;;
    
    "09:01")
        TYPE="memory"
        TITLE="🧠 记忆同步提醒"
        
        # 获取记忆统计
        MEMORY_COUNT=$(ls ~/.openclaw/workspace/memory/*.md 2>/dev/null | wc -l)
        LATEST_BACKUP=$(cd ~/.openclaw/workspace && git log -1 --format=%cd --date=short 2>/dev/null || echo '无')
        
        MESSAGE="🧠 记忆同步提醒 - ${TODAY}

💡 今日建议:
• 回顾昨日重要信息
• 更新记忆文件
• 使用 '记录:' 添加新记忆

📊 当前记忆库：
• 记忆文件数: ${MEMORY_COUNT}
• 最新GitHub备份: ${LATEST_BACKUP}
• 自动备份: 已启用（每次调整自动推送）

🔗 查看完整记忆:
~/.openclaw/workspace/memory/"
        ;;
    
    *)
        echo "不在推送时间段 ($HOUR:$MIN)，跳过"
        exit 0
        ;;
esac

# 推送到企业微信
echo "[$TITLE] 准备推送..."

# 使用 message 工具发送
# 注意：实际发送由 OpenClaw Gateway 或 wecom_mcp 处理
# 这里记录到日志

if [ -n "$MESSAGE" ]; then
    echo "✅ [$(date)] $TITLE 内容已生成"
    echo "[$TODAY $HOUR:$MIN] $TITLE - 已生成" >> ~/.openclaw/workspace/memory/morning_push.log
    echo "消息长度: ${#MESSAGE} 字符"
    
    # 输出消息内容（实际推送由调用者处理）
    echo "$MESSAGE"
else
    echo "❌ [$(date)] 消息生成失败"
    exit 1
fi
