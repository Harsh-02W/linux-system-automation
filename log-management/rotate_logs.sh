#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# rotate_logs.sh — Compress and rotate our automation script logs
#
# Keeps log files from growing forever by:
#   1. Compressing logs older than 1 day into .gz archives
#   2. Deleting compressed archives older than LOG_RETAIN_DAYS
#
# Think of it as "tidying up after ourselves" — good automation practice.
# Runs weekly via cron — see cron/crontab_setup.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../config/settings.conf"
source "$CONFIG"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_DIR/log-management.log"; }

mkdir -p "$LOG_DIR"

log "── Log rotation started ──────────────────────────────────"

COMPRESSED=0
DELETED=0

# ── Compress uncompressed logs older than 1 day ───────────────────────────────
while IFS= read -r log_file; do
    # Skip already-compressed files and the rotation log itself
    [[ "$log_file" == *.gz ]]             && continue
    [[ "$log_file" == */log-management.log ]] && continue

    gzip -9 "$log_file"
    log "Compressed: $(basename "$log_file") → $(basename "$log_file").gz"
    ((COMPRESSED++))
done < <(find "$LOG_DIR" -name "*.log" -mtime +1 -type f 2>/dev/null)

# ── Delete compressed archives beyond retention window ────────────────────────
while IFS= read -r old_archive; do
    rm -f "$old_archive"
    log "Deleted old archive: $(basename "$old_archive")"
    ((DELETED++))
done < <(find "$LOG_DIR" -name "*.log.gz" -mtime "+$LOG_RETAIN_DAYS" -type f 2>/dev/null)

log "Rotation complete — Compressed: $COMPRESSED file(s), Deleted: $DELETED old archive(s)."
log "── Log rotation finished ─────────────────────────────────"