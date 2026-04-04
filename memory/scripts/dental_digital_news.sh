#!/bin/bash
# dental_digital_news.sh - 数字化牙科进展每日推送

NTFY_TOPIC="hengkaihsu-dental-news"
NTFY_URL="https://ntfy.sh/${NTFY_TOPIC}"

# 获取当前日期
TODAY=$(date "+%Y-%m-%d")

echo "[$(date)] 开始获取数字化牙科资讯..." >> /tmp/dental_news.log

# 加载环境变量
export $(grep -v '^#' ~/.openclaw/.env | xargs) 2>/dev/null

# 使用 Tavily API 搜索最新资讯（如果有配置）
if [ -n "$TAVILY_API_KEY" ]; then
    # 使用 Tavily 搜索
    SEARCH_RESULT=$(curl -s -X POST "https://api.tavily.com/search" \
        -H "Content-Type: application/json" \
        -d "{\"api_key\": \"$TAVILY_API_KEY\", \"query\": \"digital dentistry news AI technology $TODAY\", \"search_depth\": \"advanced\", \"max_results\": 5}" 2>/dev/null)
    
    if [ -n "$SEARCH_RESULT" ]; then
        # 解析结果
        TITLE1=$(echo "$SEARCH_RESULT" | grep -o '"title":"[^"]*"' | head -1 | sed 's/"title":"//;s/"$//')
        URL1=$(echo "$SEARCH_RESULT" | grep -o '"url":"[^"]*"' | head -1 | sed 's/"url":"//;s/"$//')
        CONTENT1=$(echo "$SEARCH_RESULT" | grep -o '"content":"[^"]*"' | head -1 | sed 's/"content":"//;s/"$//' | cut -c1-200)
        
        MESSAGE="🦷 数字化牙科进展 - $TODAY

📌 $TITLE1
💡 $CONTENT1...
🔗 $URL1

更多资讯请查看邮件或搜索"
    else
        MESSAGE="🦷 数字化牙科进展 - $TODAY

今日搜索暂未获取到新资讯。
建议查看：
• Dental Economics
• Journal of Prosthodontic Research
• International Journal of Computerized Dentistry

关键词: Digital Dentistry, AI Dentistry, CAD/CAM"
    fi
else
    # 如果没有 Tavily API，提供固定资讯源
    MESSAGE="🦷 数字化牙科进展 - $TODAY

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
fi

# 推送到 ntfy
curl -s -X POST "$NTFY_URL" \
    -H "Title: 🦷 数字化牙科进展" \
    -H "Priority: default" \
    -H "Tags: tooth,mag" \
    -d "$MESSAGE"

# 记录日志
echo "[$(date)] 已推送到 ntfy.sh/$NTFY_TOPIC" >> /tmp/dental_news.log
echo "[$TODAY] $MESSAGE" >> ~/.openclaw/workspace/memory/dental_news_history.log

echo "✅ 数字化牙科资讯已推送"
