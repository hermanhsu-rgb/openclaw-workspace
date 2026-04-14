---
name: agentic-workflow-automation
description: Generate reusable multi-step agent workflow blueprints. Use for trigger/action orchestration, deterministic workflow definitions, and automation handoff artifacts.
---

# Agentic Workflow Automation

## Overview

Build workflow blueprints that can be translated into automation platforms such as n8n or internal orchestrators.

## Workflow

1. Define workflow name, trigger, and ordered steps.
2. Normalize each step into a simple execution contract.
3. Build a blueprint with dependencies and execution order.
4. Export JSON/markdown artifacts for implementation.

## Use Bundled Resources

- Run `scripts/generate_workflow_blueprint.py` for deterministic workflow output.
- Read `references/workflow-blueprint-guide.md` for step design guidance.

## Bundled Agents

### 1. Weather Fetcher (`weather-fetcher`)
Fetch real-time weather with smart outfit recommendations.
- Input: city name (default: Shanghai)
- Output: temperature, conditions, outfit suggestion

### 2. Proactive Scheduler (`proactive-scheduler`)
Schedule timed triggers for agent workflows.
- Input: job_name, cron_schedule, script_path
- Output: job_id, next_run, status

### 3. Push Notifier (`push-notifier`)
Deliver messages via Telegram, WeChat, Feishu, or ntfy.
- Input: message_file, channel
- Output: delivery_status, timestamp

## Guardrails

- Keep each step single-purpose.
- Include clear fallback behavior for failed steps.
- Test with `scripts/weather_fetch.sh` before scheduling.
