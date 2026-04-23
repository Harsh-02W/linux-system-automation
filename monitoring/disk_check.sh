#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# disk_check.sh — Monitor disk usage and alert when things get tight
#
# Checks all mounted filesystems and warns when usage crosses DISK_THRESHOLD.
# Optionally sends an email alert if ALERT_EMAIL is set in settings.conf.
#
# Run hourly via cron — see cron/crontab_setup.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../config/settings.conf"
source "$CONFIG"

log()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_DIR/monitoring.log"; }
alert() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: $*" | tee -a "$LOG_DIR/monitoring.log"; }

mkdir -p "$LOG_DIR"

ALERT_TRIGGERED=false
ALERT_BODY=""

log "── Disk check started ────────────────────────────────────"

# ── Check each mounted filesystem ────────────────────────────────────────────
while IFS= read -r line; do
    # df output: Filesystem  Size  Used  Avail  Use%  Mounted
    USAGE=$(echo "$line" | awk '{print $5}' | tr -d '%')
    MOUNT=$(echo "$line" | awk '{print $6}')
    SIZE=$(echo "$line"  | awk '{print $2}')
    USED=$(echo "$line"  | awk '{print $3}')
    AVAIL=$(echo "$line" | awk '{print $4}')

    # Skip pseudo/virtual filesystems (tmpfs, devtmpfs, etc.)
    FSTYPE=$(echo "$line" | awk '{print $1}')
    [[ "$FSTYPE" == tmpfs* || "$FSTYPE" == devtmpfs* || "$FSTYPE" == udev* ]] && continue
    [[ "$MOUNT" == /dev* || "$MOUNT" == /run* || "$MOUNT" == /sys* || "$MOUNT" == /proc* ]] && continue

    if [[ "$USAGE" -ge "$DISK_THRESHOLD" ]]; then
        alert "Disk usage at ${USAGE}% on '$MOUNT' (Used: $USED / $SIZE, Free: $AVAIL)"
        ALERT_TRIGGERED=true
        ALERT_BODY+="  ⚠  $MOUNT is at ${USAGE}% (Used: $USED / $SIZE, Free: $AVAIL)\n"
    else
        log "OK  ${USAGE}%  on '$MOUNT' (Used: $USED / $SIZE, Free: $AVAIL)"
    fi

done < <(df -h | tail -n +2)

# ── Send alert email if configured ───────────────────────────────────────────
if [[ "$ALERT_TRIGGERED" == true && -n "$ALERT_EMAIL" ]]; then
    if command -v mail &>/dev/null; then
        printf "Subject: [ALERT] Disk Usage Warning on $(hostname)\n\nThe following partitions have exceeded the ${DISK_THRESHOLD}%% threshold:\n\n%b\n\nCheck the server: $(hostname)" "$ALERT_BODY" \
            | mail -s "[ALERT] Disk Usage on $(hostname)" "$ALERT_EMAIL"
        log "Alert email sent to $ALERT_EMAIL"
    else
        log "mail command not available — skipping email alert. Install with: sudo apt install mailutils"
    fi
fi

if [[ "$ALERT_TRIGGERED" == false ]]; then
    log "All disks are within the safe threshold (< ${DISK_THRESHOLD}%). Nothing to worry about."
fi

log "── Disk check finished ───────────────────────────────────"