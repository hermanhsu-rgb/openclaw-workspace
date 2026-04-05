#!/bin/bash
# proactive_wecom_cron.sh - 定时生成推送消息到企业微信

TODAY=$(date "+%Y-%m-%d")
HOUR=$(date +%H)
MIN=$(date +%M)

# 生成消息内容
generate_dental_message() {
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
}

generate_weather_message() {
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
}

generate_memory_message() {
    echo "🧠 记忆同步提醒 - $TODAY

💡 今日建议:
• 回顾昨日重要信息
• 更新记忆文件
• 使用 '记录:' 添加新记忆

🔗 查看完整记忆:
~/.openclaw/workspace/memory/"
}

# 判断推送类型并生成消息
case "$HOUR:$MIN" in
    "08:00")
        TYPE="dental"
        TITLE="🦷 数字化牙科进展"
        MESSAGE=$(generate_dental_message)
        ;;
    "09:00")
        TYPE="weather"
        TITLE="🌤️ 早安天气提醒"
        MESSAGE=$(generate_weather_message)
        ;;
    "09:01")
        TYPE="memory"
        TITLE="🧠 记忆同步提醒"
        MESSAGE=$(generate_memory_message)
        ;;
    *)
        echo "不在推送时间段 ($HOUR:$MIN)，跳过"
        exit 0
        ;;
esac

# 直接推送到企业微信（通过 OpenClaw Gateway）
JSON_PAYLOAD=$(printf '{"channel":"wecom","target":"heng-kaihsu","content":%s}' "$(echo "$MESSAGE" | jq -Rs .)")

curl -s -X POST "http://localhost:38768/api/messages/send" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ [$(date)] $TITLE 已推送到企业微信"
    echo "[$(date)] $TITLE - 推送成功" >> ~/.openclaw/workspace/memory/proactive_cron.log
else
    echo "❌ [$(date)] $TITLE 推送失败"
    echo "[$(date)] $TITLE - 推送失败" >> ~/.openclaw/workspace/memory/proactive_cron.log
fi
