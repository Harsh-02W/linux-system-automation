#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# backup_logs.sh — Archive important system logs before rotation wipes them
#
# Backs up /var/log entries that matter for auditing and debugging.
# Runs weekly via cron — see cron/crontab_setup.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../config/settings.conf"
source "$CONFIG"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_DIR/backup.log"; }
die() { log "ERROR: $*"; exit 1; }

# Logs we care about preserving
LOGS_TO_BACKUP=(
    "/var/log/syslog"
    "/var/log/auth.log"
    "/var/log/kern.log"
    "/var/log/dpkg.log"
    "/var/log/apt/history.log"
)

TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
ARCHIVE_DIR="$BACKUP_DEST/log-archives"
ARCHIVE_FILE="$ARCHIVE_DIR/syslogs_${TIMESTAMP}.tar.gz"

mkdir -p "$ARCHIVE_DIR" "$LOG_DIR"

log "━━━ System log backup started ━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Filter to only files that actually exist
EXISTING_LOGS=()
for log_file in "${LOGS_TO_BACKUP[@]}"; do
    if [[ -f "$log_file" ]]; then
        EXISTING_LOGS+=("$log_file")
    else
        log "Skipping (not found): $log_file"
    fi
done

[[ ${#EXISTING_LOGS[@]} -eq 0 ]] && die "No log files found to back up."

log "Archiving ${#EXISTING_LOGS[@]} log file(s) → $ARCHIVE_FILE"

tar -czf "$ARCHIVE_FILE" "${EXISTING_LOGS[@]}" 2>>"$LOG_DIR/backup.log"

FILE_SIZE=$(du -sh "$ARCHIVE_FILE" | cut -f1)
log "Log archive created — Size: $FILE_SIZE"

# Clean up old log archives beyond retention window
find "$ARCHIVE_DIR" -name "syslogs_*.tar.gz" -mtime "+$BACKUP_RETAIN_DAYS" -delete
log "Old log archives beyond $BACKUP_RETAIN_DAYS days cleaned up."
log "━━━ System log backup finished ━━━━━━━━━━━━━━━━━━━━━━━━━━"