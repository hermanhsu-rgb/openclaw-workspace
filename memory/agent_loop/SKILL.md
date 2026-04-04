# Agent Loop Skill

基于 Claude Code 泄露源码架构的 OpenClaw Agent Loop 实现。

## 功能

- **多步执行**: 支持最多 10 步的自主决策循环
- **工具调用**: 自动选择和使用工具（搜索、文件操作等）
- **上下文管理**: 自动压缩防止上下文爆炸
- **人机协作**: 危险操作需要用户确认
- **安全优先**: 删除等敏感操作会询问确认

## 使用方法

### 直接运行

```bash
/root/.openclaw/agent_loop/openclaw_agent_loop.sh '搜索 GitHub AI Agent 框架'
```

### 快捷命令

```bash
# 搜索
/root/.openclaw/agent_loop/openclaw_agent_loop.sh search 'Claude Code 架构'

# 查看状态
/root/.openclaw/agent_loop/openclaw_agent_loop.sh status
```

## 架构特点

借鉴 Claude Code 泄露源码：

1. **Agent Loop**: 观察 → 决策 → 执行 → 循环
2. **工具压缩**: 防止上下文窗口爆炸
3. **Bash 优先**: 多步操作优先使用脚本
4. **权限分类**: 危险操作需确认

## 文件结构

```
~/.openclaw/agent_loop/
├── agent_loop.sh              # 完整版 Agent Loop
├── openclaw_agent_loop.sh     # OpenClaw 集成版
├── _meta.json                 # Skill 元数据
├── sessions/                  # 会话历史
└── README.md                  # 本文件
```

## 配置

在 `~/.openclaw/.env` 中设置：
- `TAVILY_API_KEY`: 用于搜索功能

## 与 Claude Code 的对比

| 特性 | Claude Code | OpenClaw Agent Loop |
|------|-------------|---------------------|
| Agent Loop | ✅ 完整 | ✅ 基础实现 |
| 工具系统 | ✅ MCP 兼容 | ✅ 部分兼容 |
| 多 Agent | ✅ Swarm | ❌ 单 Agent |
| 隐藏功能 | 44 个 flags | 逐步添加 |
| 可观测性 | ✅ 完整 | ⚠️ 基础日志 |
