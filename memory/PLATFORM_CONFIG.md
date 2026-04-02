# Platform Configuration

**Created:** 2026-04-02  
**Purpose:** Multi-platform memory sync and channel setup

---

## 🌐 Connected Platforms

| Platform | Status | Mode | User ID |
|----------|--------|------|---------|
| **Enterprise WeChat** | ✅ Active | WebSocket | heng-kaihsu |
| **Feishu** | ✅ Active | Normal | Herman (5297548510) |
| **Telegram** | ✅ Active | Polling | 5297548510 |

---

## 👤 User Identity Mapping

All platforms map to the same user:
- **Primary ID:** Herman (heng-kaihsu)
- **Telegram:** 5297548510
- **Feishu:** 5297548510

---

## 🧠 Memory Sync Architecture

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────┐
│ Enterprise WeChat│────▶│ Local Memory │────▶│   GitHub    │
└─────────────────┘     └──────────────┘     └─────────────┘
                                │
┌─────────────────┐             │
│     Feishu      │─────────────┤
│  (Shared Notes) │             │
└─────────────────┘             │
                                │
┌─────────────────┐             │
│    Telegram     │─────────────┘
└─────────────────┘
```

---

## 📋 Sync Rules

### Before Each Session:
1. Read `memory/*.md` files
2. Check Feishu shared notes
3. Pull latest from GitHub

### After Each Session:
1. Update daily memory file
2. Push to GitHub
3. Update Feishu notes (if needed)

---

## 🔗 Important Links

| Resource | URL |
|----------|-----|
| **GitHub Repo** | https://github.com/hermanhsu-rgb/ai-collaboration |
| **Feishu Shared Notes** | https://kcnr7kouatcj.feishu.cn/docx/A7hCd3EV1oXI4cxCv8ockFDPnEe |
| **Telegram Bot** | @小结巴助手 |

---

## 🔐 API Keys (Stored in ~/.openclaw/.env)

- **Tavily:** `tvly-dev-...` (search)
- **GitHub:** `ghp_...` (collaboration)
- **Gemini:** `AIzaSyC...` (14 models)

---

## 📁 File Locations

| File | Purpose |
|------|---------|
| `memory/2026-04-02.md` | Daily conversation logs |
| `memory/PLATFORM_CONFIG.md` | This file - platform setup |
| `~/.openclaw/.env` | API keys |
| `~/.openclaw/openclaw.json` | Main configuration |
