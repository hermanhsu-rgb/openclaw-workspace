---
name: summarize
description: Summarize URLs or files with the summarize CLI (web, PDFs, images, audio, YouTube).
homepage: https://summarize.sh
metadata: {"clawdbot":{"emoji":"🧾","requires":{"bins":["summarize"]},"install":[{"id":"brew","kind":"brew","formula":"steipete/tap/summarize","bins":["summarize"],"label":"Install summarize (brew)"}]}}
---

# Summarize

Fast CLI to summarize URLs, local files, and YouTube links.

## 自动使用规则（OpenClaw配置）

**遇到以下情况时，优先使用summarize处理**：
- 长文章URL（>1000字预估）
- PDF文献
- YouTube视频需要摘要
- 用户要求"摘要"、"总结"、"提取要点"

**当前配置**：
- 模型：`openai/glm-5`（腾讯Coding Plan，免费）
- API endpoint：腾讯Coding Plan
- 配置文件：`~/.summarize/config.json`

## Quick start

```bash
summarize "https://example.com" --model google/gemini-3-flash-preview
summarize "/path/to/file.pdf" --model google/gemini-3-flash-preview
summarize "https://youtu.be/dQw4w9WgXcQ" --youtube auto
```

## Model + keys

Set the API key for your chosen provider:
- OpenAI: `OPENAI_API_KEY`
- Anthropic: `ANTHROPIC_API_KEY`
- xAI: `XAI_API_KEY`
- Google: `GEMINI_API_KEY` (aliases: `GOOGLE_GENERATIVE_AI_API_KEY`, `GOOGLE_API_KEY`)

Default model is `google/gemini-3-flash-preview` if none is set.

**我们的配置**：模型已改为 `openai/glm-5`（走腾讯Coding Plan，免费），配置在 `~/.summarize/config.json`。
环境变量在 `~/.bashrc` 中设置：`OPENAI_BASE_URL` 指向腾讯API。

## Useful flags

- `--length short|medium|long|xl|xxl|<chars>`
- `--max-output-tokens <count>`
- `--extract-only` (URLs only)
- `--json` (machine readable)
- `--firecrawl auto|off|always` (fallback extraction)
- `--youtube auto` (Apify fallback if `APIFY_API_TOKEN` set)

## Config

Optional config file: `~/.summarize/config.json`

```json
{ "model": "openai/gpt-5.2" }
```

Optional services:
- `FIRECRAWL_API_KEY` for blocked sites
- `APIFY_API_TOKEN` for YouTube fallback
