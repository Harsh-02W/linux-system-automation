#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# crontab_setup.sh — Register all automation cron jobs in one shot
#
# Run this once after cloning the project to set up the full schedule.
# It's safe to run multiple times — it won't create duplicate entries.
#
# Cron schedule overview:
#   Every 15 min  → CPU & memory check
#   Every hour    → Disk check
#   Daily 2:00 AM → Home directory backup
#   Daily 7:00 AM → Health report
#   Weekly Sunday → Log rotation + cleanup, system log backup
#
# Usage:
#   bash cron/crontab_setup.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Setting up Linux System Automation cron jobs"
echo "  Project root: $PROJECT_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Make every script executable
find "$PROJECT_DIR" -name "*.sh" -exec chmod +x {} \;
echo "  ✓ Made all scripts executable"

# ── Build cron entries ────────────────────────────────────────────────────────

CRON_TAG="# linux-system-automation"

CRON_JOBS=(
    "*/15 * * * *  bash $PROJECT_DIR/monitoring/cpu_memory_check.sh  $CRON_TAG"
    "0 * * * *     bash $PROJECT_DIR/monitoring/disk_check.sh         $CRON_TAG"
    "0 2 * * *     bash $PROJECT_DIR/backup/backup_home.sh            $CRON_TAG"
    "0 7 * * *     bash $PROJECT_DIR/monitoring/health_report.sh      $CRON_TAG"
    "0 3 * * 0     bash $PROJECT_DIR/backup/backup_logs.sh            $CRON_TAG"
    "0 4 * * 0     bash $PROJECT_DIR/log-management/rotate_logs.sh    $CRON_TAG"
    "0 5 * * 0     bash $PROJECT_DIR/log-management/cleanup_old_logs.sh $CRON_TAG"
)

# ── Grab existing crontab, strip our old entries, add fresh ones ──────────────
CURRENT_CRON=$(crontab -l 2>/dev/null | grep -v "$CRON_TAG" || true)

NEW_CRON="$CURRENT_CRON"$'\n'
for job in "${CRON_JOBS[@]}"; do
    NEW_CRON+="$job"$'\n'
done

echo "$NEW_CRON" | crontab -

echo ""
echo "  ✓ Cron jobs registered! Here's your updated schedule:"
echo ""
echo "  ┌──────────────────────┬────────────────────────────────────────────────┐"
echo "  │ Schedule             │ Script                                         │"
echo "  ├──────────────────────┼────────────────────────────────────────────────┤"
echo "  │ Every 15 minutes     │ cpu_memory_check.sh                            │"
echo "  │ Every hour           │ disk_check.sh                                  │"
echo "  │ Daily at 2:00 AM     │ backup_home.sh                                 │"
echo "  │ Daily at 7:00 AM     │ health_report.sh                               │"
echo "  │ Sunday at 3:00 AM    │ backup_logs.sh                                 │"
echo "  │ Sunday at 4:00 AM    │ rotate_logs.sh                                 │"
echo "  │ Sunday at 5:00 AM    │ cleanup_old_logs.sh                            │"
echo "  └──────────────────────┴────────────────────────────────────────────────┘"
echo ""
echo "  Run 'crontab -l' to verify. All logs will appear in:"
echo "  $(grep LOG_DIR "$PROJECT_DIR/config/settings.conf" | head -1 | awk -F= '{print $2}' | tr -d ' "')"
echo ""
echo "  Done! Your system is now on autopilot. 🚀"
echo ""