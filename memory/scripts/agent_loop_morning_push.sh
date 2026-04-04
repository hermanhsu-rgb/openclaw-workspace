#!/bin/bash
# agent_loop_morning_push.sh - 使用 Agent Loop 的晨间推送

source ~/.openclaw/.env 2>/dev/null

TODAY=$(date "+%Y-%m-%d")
HOUR=$(date +%H)
MIN=$(date +%M)

LOG_FILE="/root/.openclaw/agent_loop/morning_push.log"

echo "[$(date)] ===== Agent Loop 晨间推送 =====" >> "$LOG_FILE"

# 根据时间决定推送内容
case "$HOUR:$MIN" in
    "08:00")
        REQUEST="搜索今天的数字化牙科最新进展，包括 AI 在牙科诊断、数字化印模、CAD/CAM 材料创新"
        TYPE="dental"
        ;;
    "09:00")
        REQUEST="查询上海今天的天气，包括温度、天气状况、穿衣建议"
        TYPE="weather"
        ;;
    "09:01")
        REQUEST="整理昨天的重要信息和需要回顾的记忆"
        TYPE="memory"
        ;;
    *)
        echo "不在推送时间段，跳过" >> "$LOG_FILE"
        exit 0
        ;;
esac

echo "[$(date)] 推送类型: $TYPE" >> "$LOG_FILE"
echo "[$(date)] 请求: $REQUEST" >> "$LOG_FILE"

# 使用 Agent Loop 处理
# 这里简化处理，实际应该调用 agent_loop 函数
if [ "$TYPE" = "weather" ]; then
    CITY="Shanghai"
    WEATHER=$(curl -s "wttr.in/${CITY}?format=%C|%t|%w|%h" 2>/dev/null)
    if [ -n "$WEATHER" ]; then
        CONDITION=$(echo "$WEATHER" | cut -d'|' -f1)
        TEMP=$(echo "$WEATHER" | cut -d'|' -f2)
        
        MESSAGE="🌤️ 早安！今日天气提醒 - $TODAY

📍 城市：${CITY}
🌡️ 温度：${TEMP}
☁️ 天气：${CONDITION}

👗 穿衣建议：请根据温度选择合适衣物

祝您今天愉快！"
    else
        MESSAGE="🌤️ 天气服务暂时不可用"
    fi
elif [ "$TYPE" = "dental" ]; then
    MESSAGE="🦷 数字化牙科进展 - $TODAY

📰 今日推荐关注：

1️⃣ AI在牙科诊断中的应用
   出处: Journal of Dental Research

2️⃣ 数字化印模技术新进展
   出处: International Journal of Computerized Dentistry

3️⃣ CAD/CAM 材料创新
   出处: Dental Materials

💡 提示: 配置 Tavily API 可获取实时资讯"
else
    MESSAGE="🧠 记忆同步提醒 - $TODAY

💡 今日建议:
• 回顾昨日重要信息
• 更新记忆文件
• 使用 '记录:' 添加新记忆"
fi

# 推送到企业微信
echo "$MESSAGE"
echo "[$(date)] 推送完成: $TYPE" >> "$LOG_FILE"

# 未来版本：集成真正的 Agent Loop
# /root/.openclaw/agent_loop/openclaw_agent_loop.sh "$REQUEST"
