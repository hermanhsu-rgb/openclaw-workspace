#!/bin/bash
# Unified Memory Sync Script
# 统一记忆同步脚本

echo "🔄 同步所有平台记忆..."

# 1. 从 SQLite 读取飞书记忆
echo "📖 读取飞书记忆 (SQLite)..."
sqlite3 ~/.openclaw/memory/main.sqlite "SELECT content FROM messages ORDER BY timestamp DESC LIMIT 10;" 2>/dev/null > /tmp/feishu_memory.txt || echo "SQLite 读取失败"

# 2. 合并到 Markdown
echo "📝 合并到 Markdown..."
if [ -s /tmp/feishu_memory.txt ]; then
    echo "" >> ~/.openclaw/workspace/memory/2026-04-02.md
    echo "## 飞书记忆同步 $(date +%H:%M)" >> ~/.openclaw/workspace/memory/2026-04-02.md
    cat /tmp/feishu_memory.txt >> ~/.openclaw/workspace/memory/2026-04-02.md
    echo "✅ 飞书记忆已合并"
fi

# 3. 推送到 GitHub
echo "☁️ 推送到 GitHub..."
cd ~/.openclaw/workspace 2>/dev/null || cd /tmp/ai-collaboration
git add memory/
git commit -m "自动同步: 合并飞书记忆 $(date +%Y-%m-%d %H:%M)" 2>/dev/null
git push origin main 2>/dev/null &

echo "✅ 同步完成"
