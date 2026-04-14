#!/bin/bash
# schedule_trigger.sh - Schedule proactive agent triggers
# Usage: schedule_trigger.sh <job_name> <schedule> <script_path>

JOB_NAME="${1:-morning_weather}"
SCHEDULE="${2:-0 9 * * *}"
SCRIPT_PATH="${3:-$HOME/.openclaw/workspace/skills/agentic-workflow-automation/scripts/weather_push.sh}"

CRON_DIR="$HOME/.openclaw/cron"
JOB_FILE="$CRON_DIR/proactive_${JOB_NAME}.sh"

mkdir -p "$CRON_DIR"

# Create job wrapper script
cat > "$JOB_FILE" <<EOF
#!/bin/bash
# Proactive Agent Job: ${JOB_NAME}
# Generated: $(date)

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME="$HOME"
export OPENCLAW_STATE_DIR="$HOME/.openclaw"

${SCRIPT_PATH}

echo "[\$(date)] Job ${JOB_NAME} executed" >> $HOME/.openclaw/logs/proactive_jobs.log
EOF

chmod +x "$JOB_FILE"

# Add to crontab
(crontab -l 2>/dev/null | grep -v "proactive_${JOB_NAME}"; echo "${SCHEDULE} ${JOB_FILE}") | crontab -

# Output job info
cat <<EOF
{
  "job_id": "proactive_${JOB_NAME}",
  "schedule": "${SCHEDULE}",
  "script": "${SCRIPT_PATH}",
  "status": "scheduled",
  "next_run": "See crontab -l"
}
EOF

exit 0