#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# health_report.sh — Generate a daily system health summary
#
# Produces a clean, readable snapshot of your system's current state:
#   - Uptime and load
#   - CPU, memory, disk usage
#   - Recently logged in users
#   - Failed systemd services
#   - Last 10 lines of auth log (to catch suspicious activity)
#
# Saves report to LOG_DIR and optionally emails it.
# Designed to run once daily via cron.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../config/settings.conf"
source "$CONFIG"

mkdir -p "$LOG_DIR"

REPORT_FILE="$LOG_DIR/health_report_$(date '+%Y-%m-%d').txt"

# ── Helper: Section header ────────────────────────────────────────────────────
section() { printf "\n━━━ %s ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n" "$1"; }

{
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       Daily System Health Report — $(date '+%A, %d %B %Y')       ║"
printf "║       Host: %-44s ║\n" "$(hostname)"
echo "╚══════════════════════════════════════════════════════════╝"

section "System Uptime & Load"
uptime
echo ""
echo "Kernel : $(uname -r)"
echo "OS     : $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"

section "CPU Usage"
CPU_IDLE=$(top -bn2 -d1 | grep "Cpu(s)" | tail -1 | awk '{print $8}' | tr -d '%')
CPU_USAGE=$(echo "100 - $CPU_IDLE" | bc 2>/dev/null || echo "N/A")
echo "Current CPU usage : ${CPU_USAGE}%"
echo ""
echo "Top 5 CPU-hungry processes:"
ps aux --sort=-%cpu | awk 'NR>1 && NR<=6 {printf "  %-8s %-6s %-6s %s\n", $2, $3"%", $4"%", $11}'

section "Memory Usage"
free -h
echo ""
echo "Top 5 memory-hungry processes:"
ps aux --sort=-%mem | awk 'NR>1 && NR<=6 {printf "  %-8s %-6s %-6s %s\n", $2, $3"%", $4"%", $11}'

section "Disk Usage"
df -h | grep -v "tmpfs\|devtmpfs\|udev" | column -t

section "Recent User Logins (last 10)"
last -n 10 --time-format iso 2>/dev/null || last -n 10

section "Failed Systemd Services"
FAILED_SERVICES=$(systemctl --failed --no-legend 2>/dev/null | awk '{print $1}')
if [[ -z "$FAILED_SERVICES" ]]; then
    echo "✓ No failed services — everything looks good!"
else
    echo "⚠ The following services have failed:"
    echo "$FAILED_SERVICES"
fi

section "Recent Auth Log (last 20 lines)"
if [[ -f /var/log/auth.log ]]; then
    tail -20 /var/log/auth.log
else
    echo "auth.log not found (may be at /var/log/secure on RHEL-based systems)"
fi

section "Network Interfaces"
ip -brief addr show 2>/dev/null || ifconfig 2>/dev/null | grep -E "^[a-z]|inet "

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Report generated at $(date '+%Y-%m-%d %H:%M:%S') by linux-system-automation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

} | tee "$REPORT_FILE"

echo ""
echo "Report saved to: $REPORT_FILE"

# ── Email the report if configured ───────────────────────────────────────────
if [[ -n "$ALERT_EMAIL" ]] && command -v mail &>/dev/null; then
    mail -s "[Daily Report] System Health — $(hostname) — $(date '+%Y-%m-%d')" "$ALERT_EMAIL" < "$REPORT_FILE"
    echo "Report emailed to: $ALERT_EMAIL"
fi

# ── Clean up old reports ─────────────────────────────────────────────────────
find "$LOG_DIR" -name "health_report_*.txt" -mtime "+$LOG_RETAIN_DAYS" -delete