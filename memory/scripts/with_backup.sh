#!/bin/bash
# OpenClaw 修改命令包装器
# 用法: ~/.openclaw/with_backup.sh <command>
# 在执行任何修改命令前后自动备份

set -e

OPENCLAW_DIR="${HOME}/.openclaw"
BACKUP_SCRIPT="${OPENCLAW_DIR}/auto_github_backup.sh"
LOG_FILE="${OPENCLAW_DIR}/logs/backup_wrapper.log"

# 确保日志目录存在
mkdir -p "${OPENCLAW_DIR}/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 执行备份（静默）
run_backup() {
    local phase="$1"
    log "Backup $phase starting..."
    if [ -x "$BACKUP_SCRIPT" ]; then
        if "$BACKUP_SCRIPT" >> "$LOG_FILE" 2>&1; then
            log "Backup $phase completed"
        else
            log "Backup $phase had issues (non-fatal)"
        fi
    else
        log "Backup script not found or not executable"
    fi
}

# 如果没有提供命令，只执行备份
if [ $# -eq 0 ]; then
    run_backup "manual"
    exit 0
fi

# 执行前置备份
run_backup "pre"

# 执行实际命令
log "Executing: $*"
if "$@"; then
    log "Command succeeded"
    CMD_STATUS=0
else
    log "Command failed with code $?"
    CMD_STATUS=$?
fi

# 执行后置备份（无论命令成功与否）
run_backup "post"

exit $CMD_STATUS
