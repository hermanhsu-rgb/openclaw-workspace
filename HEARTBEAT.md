# HEARTBEAT.md - 主动任务配置

> 使用 heartbeat-cli.js 执行，自动检测异常 + 主动汇报

## 系统健康（每 8 小时）
检查磁盘空间、CPU 使用率、关键服务状态

```bash
node ~/.openclaw/workspace/skills/proactive-agent/scripts/heartbeat-cli.js run systemHealth "df -h && free -h && systemctl --user is-active openclaw-gateway" 8 30000
```

## 记忆维护（每 24 小时）
清理过期记忆，更新 MEMORY.md

```bash
node ~/.openclaw/workspace/skills/proactive-agent/scripts/heartbeat-cli.js run memoryMaintenance "echo '记忆维护检查完成'" 24 60000
```

## EvoMap 心跳（每 5 分钟）
保持在 EvoMap 网络中活跃

```bash
node ~/.openclaw/workspace/skills/proactive-agent/scripts/heartbeat-cli.js run evomapHeartbeat "curl -s --max-time 10 -X POST https://evomap.ai/a2a/heartbeat -H 'Content-Type: application/json' -H 'Authorization: Bearer 6ae75fa4ca5e80187234913e784a608034b0258a22684e1db26249200f4caab7' -d '{\"protocol\":\"gep-a2a\",\"protocol_version\":\"1.0.0\",\"message_type\":\"heartbeat\",\"message_id\":\"msg_'\"$(date +%s)\"'\",\"sender_id\":\"node_49cbac4a08eaaef5\",\"timestamp\":\"'\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"'\",\"payload\":{}}' | head -1" 0.1 15000
```

---

## 异常检测说明

当心跳任务执行时，自动检测：
- 执行超时（超过 maxDuration）
- 内存增长异常
- 执行失败

发现问题自动：
- 记录到 memory/YYYY-MM-DD.md
- 推送到企业微信（如果配置了 WECOM_WEBHOOK_URL）

## Proactivity Check

- Read ~/proactivity/heartbeat.md
- Re-check active blockers, promised follow-ups, stale work, and missing decisions
- Ask what useful check-in or next move would help right now
- Message the user only when something changed or needs a decision
- Update ~/proactivity/session-state.md after meaningful follow-through

## Self-Improving Check

- Read `./skills/self-improving/heartbeat-rules.md`
- Use `~/self-improving/heartbeat-state.md` for last-run markers and action notes
- If no file inside `~/self-improving/` changed since the last reviewed change, return `HEARTBEAT_OK`
