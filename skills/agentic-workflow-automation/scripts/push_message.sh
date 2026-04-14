#!/bin/bash
# push_message.sh - Push messages via configured channels
# Usage: push_message.sh <message_file> [channel]

MESSAGE_FILE="${1:-/dev/stdin}"
CHANNEL="${2:-telegram}"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

if [ ! -f "$MESSAGE_FILE" ] && [ "$MESSAGE_FILE" != "/dev/stdin" ]; then
    echo "❌ Message file not found: $MESSAGE_FILE"
    exit 1
fi

MESSAGE=$(cat "$MESSAGE_FILE")

# Channel-specific delivery
case "$CHANNEL" in
    telegram|tg)
        # Use lightclawbot or direct Telegram API
        if command -v openclaw &> /dev/null; then
            openclaw message send --target "$TELEGRAM_USER_ID" --message "$MESSAGE" 2>&1
            STATUS="sent_via_openclaw"
        else
            # Fallback to webhook
            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -d "chat_id=${TELEGRAM_USER_ID}" \
                -d "text=${MESSAGE}" \
                -d "parse_mode=Markdown" 2>&1
            STATUS="sent_via_api"
        fi
        ;;

    wecom|wx)
        # Enterprise WeChat webhook
        WEBHOOK_URL=$(cat ~/.openclaw/.wecom_webhook_config 2>/dev/null)
        if [ -n "$WEBHOOK_URL" ]; then
            curl -s -X POST "$WEBHOOK_URL" \
                -H 'Content-Type: application/json' \
                -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"${MESSAGE}\"}}" 2>&1
            STATUS="sent_via_wecom"
        else
            echo "⚠️ WeChat webhook not configured"
            STATUS="failed_no_config"
        fi
        ;;

    feishu|fs)
        # Feishu webhook
        FEISHU_WEBHOOK=$(cat ~/.openclaw/.feishu_webhook_config 2>/dev/null)
        if [ -n "$FEISHU_WEBHOOK" ]; then
            curl -s -X POST "$FEISHU_WEBHOOK" \
                -H 'Content-Type: application/json' \
                -d "{\"msg_type\":\"text\",\"content\":{\"text\":\"${MESSAGE}\"}}" 2>&1
            STATUS="sent_via_feishu"
        else
            echo "⚠️ Feishu webhook not configured"
            STATUS="failed_no_config"
        fi
        ;;

    ntfy)
        # ntfy.sh push
        NTFY_TOPIC=$(cat ~/.openclaw/.ntfy_topic 2>/dev/null || echo "openclaw-notifications")
        curl -s -d "$MESSAGE" "https://ntfy.sh/${NTFY_TOPIC}" 2>&1
        STATUS="sent_via_ntfy"
        ;;

    *)
        echo "❌ Unknown channel: $CHANNEL"
        echo "Available: telegram, wecom, feishu, ntfy"
        exit 1
        ;;
esac

# Log delivery
LOG_FILE="$HOME/.openclaw/logs/proactive_push.log"
mkdir -p "$(dirname "$LOG_FILE")"
echo "[$TIMESTAMP] channel=$CHANNEL status=$STATUS message_length=${#MESSAGE}" >> "$LOG_FILE"

# Output result
cat <<EOF
{
  "delivery_status": "$STATUS",
  "channel_used": "$CHANNEL",
  "timestamp": "$TIMESTAMP",
  "message_length": ${#MESSAGE}
}
EOF

exit 0