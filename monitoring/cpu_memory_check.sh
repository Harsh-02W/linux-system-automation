#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# cpu_memory_check.sh — Monitor CPU and RAM usage, catch runaway processes
#
# Checks current CPU and memory usage, logs them, and alerts when either
# crosses the configured thresholds. Also shows the top 5 hungry processes.
#
# Run every 15 minutes via cron — see cron/crontab_setup.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../config/settings.conf"
source "$CONFIG"

log()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_DIR/monitoring.log"; }
alert() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: $*" | tee -a "$LOG_DIR/monitoring.log"; }

mkdir -p "$LOG_DIR"

# ── CPU Usage ─────────────────────────────────────────────────────────────────
# Sample over 1 second for a more stable reading
CPU_IDLE=$(top -bn2 -d1 | grep "Cpu(s)" | tail -1 | awk '{print $8}' | tr -d '%')
CPU_USAGE=$(echo "100 - $CPU_IDLE" | bc 2>/dev/null || echo "0")
CPU_USAGE=${CPU_USAGE%.*}  # Trim decimals

# ── Memory Usage ──────────────────────────────────────────────────────────────
MEM_TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
MEM_USED=$(free -m  | awk '/^Mem:/ {print $3}')
MEM_FREE=$(free -m  | awk '/^Mem:/ {print $4}')
MEM_USAGE=$(echo "scale=0; $MEM_USED * 100 / $MEM_TOTAL" | bc)

log "── CPU & Memory check ───────────────────────────────────"
log "CPU  : ${CPU_USAGE}% used  (threshold: ${CPU_THRESHOLD}%)"
log "RAM  : ${MEM_USAGE}% used  (${MEM_USED}MB / ${MEM_TOTAL}MB, ${MEM_FREE}MB free)"

ALERT_TRIGGERED=false

# ── Check CPU threshold ───────────────────────────────────────────────────────
if [[ "$CPU_USAGE" -ge "$CPU_THRESHOLD" ]]; then
    alert "CPU usage is HIGH at ${CPU_USAGE}% (threshold: ${CPU_THRESHOLD}%)"
    ALERT_TRIGGERED=true
fi

# ── Check Memory threshold ────────────────────────────────────────────────────
if [[ "$MEM_USAGE" -ge "$MEM_THRESHOLD" ]]; then
    alert "Memory usage is HIGH at ${MEM_USAGE}% — ${MEM_USED}MB of ${MEM_TOTAL}MB used"
    ALERT_TRIGGERED=true
fi

# ── Top 5 processes by CPU ────────────────────────────────────────────────────
log "Top 5 processes by CPU:"
ps aux --sort=-%cpu | awk 'NR>1 && NR<=6 {printf "  [%s] PID:%-7s CPU:%-6s MEM:%-6s %s\n", NR-1, $2, $3"%", $4"%", $11}' \
    | tee -a "$LOG_DIR/monitoring.log"

# ── Top 5 processes by Memory ─────────────────────────────────────────────────
log "Top 5 processes by Memory:"
ps aux --sort=-%mem | awk 'NR>1 && NR<=6 {printf "  [%s] PID:%-7s CPU:%-6s MEM:%-6s %s\n", NR-1, $2, $3"%", $4"%", $11}' \
    | tee -a "$LOG_DIR/monitoring.log"

# ── Send alert email if needed ────────────────────────────────────────────────
if [[ "$ALERT_TRIGGERED" == true && -n "$ALERT_EMAIL" ]]; then
    if command -v mail &>/dev/null; then
        {
            echo "Resource usage alert on $(hostname) at $(date)"
            echo ""
            echo "CPU Usage  : ${CPU_USAGE}%  (threshold: ${CPU_THRESHOLD}%)"
            echo "RAM Usage  : ${MEM_USAGE}%  (${MEM_USED}MB / ${MEM_TOTAL}MB)"
            echo ""
            echo "Top processes by CPU:"
            ps aux --sort=-%cpu | awk 'NR>1 && NR<=6 {print $2, $3"%", $11}'
        } | mail -s "[ALERT] High Resource Usage on $(hostname)" "$ALERT_EMAIL"
        log "Alert email sent to $ALERT_EMAIL"
    fi
fi

if [[ "$ALERT_TRIGGERED" == false ]]; then
    log "All resource levels are normal. System is healthy."
fi

log "── CPU & Memory check finished ──────────────────────────"