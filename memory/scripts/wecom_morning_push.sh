#!/bin/bash
# wecom_morning_push.sh - 晨间推送（牙科资讯 + 天气提醒 + 记忆同步）
# 通过 OpenClaw message 工具推送到企业微信

USER="heng-kaihsu"
TODAY=$(date "+%Y-%m-%d")
HOUR=$(date +%H)
MIN=$(date +%M)

# 根据时间判断推送类型
if [ "$HOUR" = "08" ]; then
    TYPE="dental"
    TITLE="🦷 数字化牙科进展"
elif [ "$HOUR" = "09" ] && [ "$MIN" = "00" ]; then
    TYPE="weather"
    TITLE="🌤️ 早安天气提醒"
elif [ "$HOUR" = "09" ] && [ "$MIN" = "01" ]; then
    TYPE="memory"
    TITLE="🧠 记忆同步提醒"
else
    TYPE="default"
    TITLE="📋 定时提醒"
fi

# 生成消息内容
generate_message() {
    case "$TYPE" in
        dental)
            echo "🦷 数字化牙科进展 - $TODAY

📰 今日推荐关注：

1️⃣ AI在牙科诊断中的应用
   出处: Journal of Dental Research

2️⃣ 数字化印模技术新进展
   出处: International Journal of Computerized Dentistry

3️⃣ CAD/CAM 材料创新
   出处: Dental Materials

💡 提示: 配置 Tavily API 可获取实时资讯

🔗 推荐网站:
• dentaleconomics.com
• idcdental.com
• jprosthodont.org"
            ;;
        weather)
            CITY="Shanghai"
            WEATHER_RAW=$(curl -s "wttr.in/${CITY}?format=%C|%t|%w|%h" 2>/dev/null)
            
            if [ -n "$WEATHER_RAW" ]; then
                CONDITION=$(echo "$WEATHER_RAW" | cut -d'|' -f1 | sed 's/^[[:space:]]*//')
                TEMP=$(echo "$WEATHER_RAW" | cut -d'|' -f2 | sed 's/^[[:space:]]*//')
                WIND=$(echo "$WEATHER_RAW" | cut -d'|' -f3 | sed 's/^[[:space:]]*//')
                HUMIDITY=$(echo "$WEATHER_RAW" | cut -d'|' -f4 | sed 's/^[[:space:]]*//')
                
                # 穿衣建议
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
                
                echo "🌤️ 早安！今日天气提醒 - $TODAY

📍 城市：${CITY}
🌡️ 温度：${TEMP}
☁️ 天气：${CONDITION}
💨 风力：${WIND}
💧 湿度：${HUMIDITY}

👗 穿衣建议：${OUTFIT}

祝您今天愉快！"
            else
                echo "🌤️ 早安！今日天气服务暂时不可用，请稍后查看。"
            fi
            ;;
        memory)
            echo "🧠 记忆同步提醒 - $TODAY

💡 今日建议:
• 回顾昨日重要信息
• 更新记忆文件
• 使用 '记录:' 添加新记忆

🔗 查看完整记忆:
~/.openclaw/workspace/memory/"
            ;;
        *)
            echo "📋 定时提醒 - $TODAY"
            ;;
    esac
}

MESSAGE=$(generate_message)

# 保存到消息队列（OpenClaw 会读取并发送）
mkdir -p ~/.openclaw/proactive_messages
MSG_FILE="~/.openclaw/proactive_messages/${TYPE}_$(date +%s).json"

# JSON 格式，包含目标用户和消息内容
cat > "$MSG_FILE" << EOF
{
  "target": "$USER",
  "channel": "wecom",
  "type": "$TYPE",
  "title": "$TITLE",
  "content": $(echo "$MESSAGE" | jq -Rs .),
  "timestamp": "$(date -Iseconds)"
}
EOF

# 记录日志
echo "[$(date)] 已生成 $TYPE 消息队列: $MSG_FILE" >> ~/.openclaw/workspace/memory/wecom_push.log

# 同时保留 ntfy 推送（可选）
NTFY_TOPIC="hengkaihsu-${TYPE}"
curl -s -X POST "https://ntfy.sh/${NTFY_TOPIC}" \
    -H "Title: $TITLE" \
    -H "Priority: default" \
    -d "$MESSAGE" > /dev/null 2>&1 || true

echo "✅ $TITLE 已加入推送队列"
