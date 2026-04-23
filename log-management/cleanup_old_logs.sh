#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# cleanup_old_logs.sh — Sweep out stale logs from system log directories
#
# Targets common noisy log directories that can bloat disk over time:
#   - /var/log/journal  (systemd journal, can grow huge)
#   - /tmp              (old temp files left behind)
#   - Our own LOG_DIR   (belt-and-suspenders safety net)
#
# Runs weekly via cron — see cron/crontab_setup.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../config/settings.conf"
source "$CONFIG"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_DIR/log-management.log"; }

mkdir -p "$LOG_DIR"

log "── Log cleanup started ───────────────────────────────────"

# ── Vacuum systemd journal logs ───────────────────────────────────────────────
# Keep only the last 2 weeks of journal entries
if command -v journalctl &>/dev/null; then
    BEFORE=$(journalctl --disk-usage 2>/dev/null | awk '{print $NF}' || echo "unknown")
    journalctl --vacuum-time="${LOG_RETAIN_DAYS}d" &>>"$LOG_DIR/log-management.log"
    AFTER=$(journalctl --disk-usage 2>/dev/null | awk '{print $NF}' || echo "unknown")
    log "Journal vacuumed — Before: $BEFORE, After: $AFTER"
else
    log "journalctl not available — skipping journal vacuum."
fi

# ── Clean up /tmp files older than 7 days ─────────────────────────────────────
TMP_COUNT=$(find /tmp -maxdepth 1 -mtime +7 -type f 2>/dev/null | wc -l)
if [[ $TMP_COUNT -gt 0 ]]; then
    find /tmp -maxdepth 1 -mtime +7 -type f -delete 2>/dev/null || true
    log "Removed $TMP_COUNT stale file(s) from /tmp"
else
    log "/tmp is clean — no stale files found."
fi

# ── Clean up our own old compressed logs as a safety net ─────────────────────
OLD_AUTOMATION_LOGS=$(find "$LOG_DIR" -name "*.gz" -mtime "+$LOG_RETAIN_DAYS" 2>/dev/null | wc -l)
if [[ $OLD_AUTOMATION_LOGS -gt 0 ]]; then
    find "$LOG_DIR" -name "*.gz" -mtime "+$LOG_RETAIN_DAYS" -delete
    log "Removed $OLD_AUTOMATION_LOGS old compressed automation log(s)."
fi

# ── Show current log directory size ──────────────────────────────────────────
LOG_SIZE=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)
log "Current automation log directory size: $LOG_SIZE"

log "── Log cleanup finished ──────────────────────────────────"