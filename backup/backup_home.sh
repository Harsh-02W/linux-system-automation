#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# backup_home.sh — Daily compressed backup of /home with retention policy
#
# What it does:
#   - Creates a timestamped .tar.gz of BACKUP_SOURCE (default: /home)
#   - Stores it in BACKUP_DEST
#   - Automatically removes backups older than BACKUP_RETAIN_DAYS
#   - Logs success/failure with file size info
#
# Designed to be run daily via cron. See cron/crontab_setup.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../config/settings.conf"
source "$CONFIG"

log()     { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_DIR/backup.log"; }
log_err() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_DIR/backup.log" >&2; }
die()     { log_err "$*"; exit 1; }

mkdir -p "$BACKUP_DEST" "$LOG_DIR"

TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
BACKUP_FILE="$BACKUP_DEST/home_backup_${TIMESTAMP}.tar.gz"

log "━━━ Backup started ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Source  : $BACKUP_SOURCE"
log "Target  : $BACKUP_FILE"

# ── Run the backup ────────────────────────────────────────────────────────────
START_TIME=$(date +%s)

if tar \
    --exclude='*.cache' \
    --exclude='*/.local/share/Trash' \
    --exclude='*/node_modules' \
    --exclude='*/__pycache__' \
    -czf "$BACKUP_FILE" \
    -C "$(dirname "$BACKUP_SOURCE")" "$(basename "$BACKUP_SOURCE")" \
    2>>"$LOG_DIR/backup.log"; then

    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    FILE_SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)

    log "Backup completed in ${ELAPSED}s — Size: $FILE_SIZE"
    log "Saved to: $BACKUP_FILE"
else
    die "Backup FAILED for $BACKUP_SOURCE. Check the log above for details."
fi

# ── Enforce retention policy ─────────────────────────────────────────────────
log "Cleaning up backups older than $BACKUP_RETAIN_DAYS days..."

DELETED_COUNT=0
while IFS= read -r old_backup; do
    rm -f "$old_backup"
    log "Removed old backup: $(basename "$old_backup")"
    ((DELETED_COUNT++))
done < <(find "$BACKUP_DEST" -name "home_backup_*.tar.gz" -mtime "+$BACKUP_RETAIN_DAYS")

if [[ $DELETED_COUNT -eq 0 ]]; then
    log "No old backups to clean up — all within retention window."
else
    log "Removed $DELETED_COUNT old backup(s)."
fi

# ── Show current backup inventory ────────────────────────────────────────────
BACKUP_COUNT=$(find "$BACKUP_DEST" -name "home_backup_*.tar.gz" | wc -l)
TOTAL_SIZE=$(du -sh "$BACKUP_DEST" 2>/dev/null | cut -f1)

log "Current backup inventory: $BACKUP_COUNT file(s) using $TOTAL_SIZE total."
log "━━━ Backup finished ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"