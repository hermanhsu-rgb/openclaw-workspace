#!/bin/bash
# OpenClaw 自动 GitHub 备份脚本
# 每次系统调整后自动执行，无需确认
# 如需推送到 GitHub，请设置 GITHUB_TOKEN 环境变量

set -e

OPENCLAW_DIR="${HOME}/.openclaw"
WORKSPACE_DIR="${OPENCLAW_DIR}/workspace"
MEMORY_DIR="${WORKSPACE_DIR}/memory"
BACKUP_LOG="${MEMORY_DIR}/auto_github_backup.log"
GITHUB_REPO="hermanhsu-rgb/openclaw-workspace"

# 创建日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$BACKUP_LOG"
}

# 同步关键文件到 workspace
sync_files() {
    log "开始同步文件到 workspace..."
    
    # 同步 agent_loop
    if [ -d "${OPENCLAW_DIR}/agent_loop" ]; then
        rm -rf "${MEMORY_DIR}/agent_loop"
        cp -r "${OPENCLAW_DIR}/agent_loop" "${MEMORY_DIR}/"
        log "✓ agent_loop 已同步"
    fi
    
    # 同步关键配置文件
    cp "${OPENCLAW_DIR}/openclaw.json" "${MEMORY_DIR}/" 2>/dev/null || true
    cp "${OPENCLAW_DIR}/claude_desktop_config.json" "${MEMORY_DIR}/" 2>/dev/null || true
    
    # 同步核心脚本
    mkdir -p "${MEMORY_DIR}/scripts"
    cp "${OPENCLAW_DIR}/morning_push.sh" "${MEMORY_DIR}/scripts/" 2>/dev/null || true
    cp "${OPENCLAW_DIR}/wecom_morning_push.sh" "${MEMORY_DIR}/scripts/" 2>/dev/null || true
    cp "${OPENCLAW_DIR}/proactive_wecom_cron.sh" "${MEMORY_DIR}/scripts/" 2>/dev/null || true
    cp "${OPENCLAW_DIR}/agent_loop_morning_push.sh" "${MEMORY_DIR}/scripts/" 2>/dev/null || true
    cp "${OPENCLAW_DIR}/dental_digital_news.sh" "${MEMORY_DIR}/scripts/" 2>/dev/null || true
    cp "${OPENCLAW_DIR}/auto_github_backup.sh" "${MEMORY_DIR}/scripts/" 2>/dev/null || true
    cp "${OPENCLAW_DIR}/with_backup.sh" "${MEMORY_DIR}/scripts/" 2>/dev/null || true
    
    log "✓ 文件同步完成"
}

# 配置 GitHub 远程 URL（使用 Token 如果可用）
configure_remote() {
    cd "$WORKSPACE_DIR"
    
    # 尝试从 .env 文件加载 token
    if [ -f "${OPENCLAW_DIR}/.env" ]; then
        source "${OPENCLAW_DIR}/.env" 2>/dev/null || true
    fi
    
    # 使用 GH_TOKEN 或 GITHUB_TOKEN
    TOKEN="${GH_TOKEN:-$GITHUB_TOKEN}"
    
    if [ -n "$TOKEN" ]; then
        # 使用 Token 认证
        git remote set-url origin "https://${TOKEN}@github.com/${GITHUB_REPO}.git" 2>/dev/null || true
        log "✓ 已配置 GitHub Token 认证"
    else
        # 检查是否已配置其他认证方式
        if ! git ls-remote origin > /dev/null 2>&1; then
            log "⚠ GitHub Token 未设置，将仅提交到本地仓库"
            return 1
        fi
    fi
}

# GitHub 备份
github_backup() {
    cd "$WORKSPACE_DIR"
    
    # 检查是否有变更
    if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
        log "没有变更需要提交"
        return 0
    fi
    
    log "检测到变更，开始备份到 GitHub..."
    
    # 配置远程（尝试使用 Token）
    configure_remote || true
    
    # 添加所有变更
    git add -A
    
    # 提交（带时间戳）
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    COMMIT_MSG="Auto backup: ${TIMESTAMP}"
    DETAILS="$(git diff --name-only --cached | head -20 | sed 's/^/- /')"
    if [ "$(git diff --name-only --cached | wc -l)" -gt 20 ]; then
        DETAILS="${DETAILS}
- ... and $(($(git diff --name-only --cached | wc -l) - 20)) more files"
    fi
    
    git commit -m "$COMMIT_MSG" -m "$DETAILS" || {
        log "✗ 提交失败"
        return 1
    }
    
    # 推送到 GitHub（静默模式）
    if git push origin master > /dev/null 2>&1; then
        log "✓ GitHub 推送成功"
        log "  Commit: $(git rev-parse --short HEAD)"
    else
        log "⚠ GitHub 推送失败（可能需要配置 GITHUB_TOKEN）"
        return 1
    fi
}

# 主执行流程
main() {
    log "=== 自动备份开始 ==="
    
    # 检查 git 配置
    if [ ! -d "${WORKSPACE_DIR}/.git" ]; then
        log "✗ 未找到 git 仓库"
        return 1
    fi
    
    sync_files
    github_backup
    
    log "=== 自动备份完成 ==="
    echo "" >> "$BACKUP_LOG"
}

main "$@"
