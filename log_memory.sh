#!/bin/bash
# log_memory.sh - 记录统一记忆的脚本

# 参数:
# $1: 平台 (e.g., "Feishu", "WeCom", "Telegram")
# $2: 用户 (e.g., "heng-kaihsu")
# $3: 要记录的内容

# 检查参数
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "Usage: $0 <platform> <user> <content>"
  exit 1
fi

PLATFORM=$1
USER=$2
CONTENT=$3
MEMORY_FILE="memory/UNIFIED_MEMORY.md"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# 写入文件
# 格式: [时间] [平台] [用户]: <内容>
echo "[$TIMESTAMP] [$PLATFORM] [$USER]: $CONTENT" >> $MEMORY_FILE

echo "✅ 记忆已记录到 $MEMORY_FILE"
