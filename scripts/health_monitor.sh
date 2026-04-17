#!/bin/bash
# =============================================================================
# health_monitor.sh
# Checks CPU, memory, disk, and running services — then writes a health report.
# Designed to run every few minutes via cron and alert when things look off.
# =============================================================================

# --- Thresholds (tweak these to match your system) ---
CPU_THRESHOLD=80        # Alert if CPU usage goes above this %
MEM_THRESHOLD=85        # Alert if memory usage goes above this %
DISK_THRESHOLD=90       # Alert if any disk partition is above this %

# --- Services to watch --- (add or remove as needed)
SERVICES_TO_CHECK=(
    "ssh"
    "cron"
    "rsyslog"
)

# --- Log/Report paths ---
LOG_DIR="$(dirname "$0")/../logs"
LOG_FILE="$LOG_DIR/health_monitor.log"
REPORT_FILE="$LOG_DIR/health_report.txt"
mkdir -p "$LOG_DIR"

# Optional: email alert recipient
ALERT_EMAIL=""

# --- Helpers ---

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

send_alert() {
    local subject="$1"
    local body="$2"

    if [[ -n "$ALERT_EMAIL" ]] && command -v mail &>/dev/null; then
        echo "$body" | mail -s "$subject" "$ALERT_EMAIL"
    fi
}

# =============================================================================
# CPU check
# Uses /proc/stat to calculate usage over a 1-second sample window
# =============================================================================
check_cpu() {
    # Read two snapshots 1 second apart and compute the delta
    local cpu1 idle1 cpu2 idle2

    read -r _ cpu1 <<< "$(grep '^cpu ' /proc/stat | awk '{print $0, $1+$2+$3+$4+$5+$6+$7+$8}')"
    read -r _ _ _ _ idle1 _ <<< "$(grep '^cpu ' /proc/stat)"
    sleep 1
    read -r _ cpu2 <<< "$(grep '^cpu ' /proc/stat | awk '{print $0, $1+$2+$3+$4+$5+$6+$7+$8}')"
    read -r _ _ _ _ idle2 _ <<< "$(grep '^cpu ' /proc/stat)"

    # Simpler and more reliable: use the 'top' batch output for a 1-sample read
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}' | cut -d'.' -f1)

    echo "$cpu_usage"
}

# =============================================================================
# Memory check
# Returns memory usage as a percentage
# =============================================================================
check_memory() {
    local mem_total mem_available mem_used mem_pct

    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    mem_used=$((mem_total - mem_available))
    mem_pct=$(( (mem_used * 100) / mem_total ))

    echo "$mem_pct"
}

# Pretty print memory stats
memory_details() {
    free -h | awk 'NR==1 || NR==2'
}

# =============================================================================
# Disk check
# Scans all mounted partitions and reports any over the threshold
# =============================================================================
check_disk() {
    local alerts=()

    while read -r usage mount; do
        local pct="${usage%%%}"   # strip the % sign
        if [[ $pct -ge $DISK_THRESHOLD ]]; then
            alerts+=("$mount at ${usage} used")
        fi
    done < <(df -h --output=pcent,target | tail -n +2 | tr -d ' ')

    echo "${alerts[@]}"
}

disk_details() {
    df -h --output=target,size,used,avail,pcent | column -t
}

# =============================================================================
# Service check
# Checks each listed service and reports any that are not running
# =============================================================================
check_services() {
    local down_services=()

    for service in "${SERVICES_TO_CHECK[@]}"; do
        if ! systemctl is-active --quiet "$service" 2>/dev/null; then
            down_services+=("$service")
        fi
    done

    echo "${down_services[@]}"
}

# =============================================================================
# Top 5 resource-hungry processes (useful context in any health report)
# =============================================================================
top_processes() {
    echo "--- Top 5 by CPU ---"
    ps aux --sort=-%cpu | awk 'NR<=6 {printf "%-15s %-10s %-10s %s\n", $1, $2, $3, $11}' | column -t

    echo ""
    echo "--- Top 5 by Memory ---"
    ps aux --sort=-%mem | awk 'NR<=6 {printf "%-15s %-10s %-10s %s\n", $1, $2, $4, $11}' | column -t
}

# =============================================================================
# Generate a full health report and write it to REPORT_FILE
# =============================================================================
generate_report() {
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    local cpu_pct
    cpu_pct=$(check_cpu)

    local mem_pct
    mem_pct=$(check_memory)

    local disk_alerts
    disk_alerts=$(check_disk)

    local service_alerts
    service_alerts=$(check_services)

    # --- Build the report ---
    {
        echo "=============================================="
        echo "  System Health Report — $(hostname)"
        echo "  Generated: $timestamp"
        echo "=============================================="
        echo ""

        # CPU
        echo "[ CPU ]"
        if [[ -n "$cpu_pct" && "$cpu_pct" -ge "$CPU_THRESHOLD" ]]; then
            echo "  Status : WARNING — CPU at ${cpu_pct}% (threshold: ${CPU_THRESHOLD}%)"
        else
            echo "  Status : OK — CPU at ${cpu_pct:-N/A}%"
        fi
        echo ""

        # Memory
        echo "[ Memory ]"
        if [[ "$mem_pct" -ge "$MEM_THRESHOLD" ]]; then
            echo "  Status : WARNING — Memory at ${mem_pct}% (threshold: ${MEM_THRESHOLD}%)"
        else
            echo "  Status : OK — Memory at ${mem_pct}%"
        fi
        memory_details | sed 's/^/  /'
        echo ""

        # Disk
        echo "[ Disk ]"
        if [[ -n "$disk_alerts" ]]; then
            echo "  Status : WARNING"
            for alert in "${disk_alerts[@]}"; do
                echo "  ! $alert"
            done
        else
            echo "  Status : OK — all partitions below ${DISK_THRESHOLD}%"
        fi
        disk_details | sed 's/^/  /'
        echo ""

        # Services
        echo "[ Services ]"
        local all_ok=true
        for service in "${SERVICES_TO_CHECK[@]}"; do
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                echo "  ✓ $service is running"
            else
                echo "  ✗ $service is NOT running"
                all_ok=false
            fi
        done
        echo ""

        # Top processes
        echo "[ Processes ]"
        top_processes | sed 's/^/  /'
        echo ""

        echo "=============================================="
        echo "  Report saved to: $REPORT_FILE"
        echo "=============================================="

    } | tee "$REPORT_FILE"

    # Log a short summary line
    log "INFO" "Health check — CPU: ${cpu_pct:-?}% | Mem: ${mem_pct}% | Disk alerts: ${disk_alerts:-none} | Service alerts: ${service_alerts:-none}"

    # Send an alert if anything is outside normal bounds
    local alert_body=""
    [[ -n "$cpu_pct" && "$cpu_pct" -ge "$CPU_THRESHOLD" ]] && \
        alert_body+="CPU is at ${cpu_pct}%\n"
    [[ "$mem_pct" -ge "$MEM_THRESHOLD" ]] && \
        alert_body+="Memory is at ${mem_pct}%\n"
    [[ -n "$disk_alerts" ]] && \
        alert_body+="Disk issues: $disk_alerts\n"
    [[ -n "$service_alerts" ]] && \
        alert_body+="Services down: $service_alerts\n"

    if [[ -n "$alert_body" ]]; then
        log "WARN" "Threshold exceeded — sending alert"
        send_alert "[ALERT] $(hostname) health issue" "$(echo -e "$alert_body")"
    fi
}

# =============================================================================
# Quick check — just prints a one-liner status, no full report
# Great for running manually to see if anything is obviously wrong
# =============================================================================
quick_check() {
    local cpu_pct
    cpu_pct=$(check_cpu)

    local mem_pct
    mem_pct=$(check_memory)

    echo ""
    echo "Quick status on $(hostname) — $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "  CPU     : ${cpu_pct:-?}%  $([ "${cpu_pct:-0}" -ge "$CPU_THRESHOLD" ] && echo '⚠ HIGH' || echo '✓ OK')"
    echo "  Memory  : ${mem_pct}%  $([ "$mem_pct" -ge "$MEM_THRESHOLD" ] && echo '⚠ HIGH' || echo '✓ OK')"
    echo "  Disk    : $([ -z "$(check_disk)" ] && echo '✓ OK' || echo "⚠ $(check_disk)")"
    echo ""
    echo "  Services:"
    for service in "${SERVICES_TO_CHECK[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo "    ✓ $service"
        else
            echo "    ✗ $service (DOWN)"
        fi
    done
    echo ""
}

# =============================================================================
# Main
# =============================================================================
main() {
    local action="${1:-report}"

    case "$action" in
        report)
            generate_report
            ;;
        quick)
            quick_check
            ;;
        *)
            echo ""
            echo "Usage: $0 <action>"
            echo ""
            echo "  report — full health report written to $REPORT_FILE"
            echo "  quick  — one-liner status check (no file written)"
            echo ""
            ;;
    esac
}

main "$@"