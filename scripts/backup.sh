#!/bin/bash
# =============================================================================
# backup.sh
# Backs up specified directories to a local destination using rsync.
# Keeps dated snapshots and automatically cleans up old ones.
# Schedule this with cron to run it daily without thinking about it.
# =============================================================================

# --- Configuration ---
# Edit these to match your machine. Separate multiple sources with spaces.
BACKUP_SOURCES=(
    "/etc"
    "/home"
    "/var/log"
)
BACKUP_DEST="/var/backups/system-snapshots"   # Where backups land
RETENTION_DAYS=7                              # How many days of backups to keep
LOG_DIR="$(dirname "$0")/../logs"
LOG_FILE="$LOG_DIR/backup.log"
mkdir -p "$LOG_DIR" "$BACKUP_DEST"

# Optional: set an email address to receive failure alerts
# Leave blank to skip email notifications
ALERT_EMAIL=""

# --- Helpers ---

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Send an email alert (only if mailutils is installed and ALERT_EMAIL is set)
send_alert() {
    local subject="$1"
    local body="$2"

    if [[ -n "$ALERT_EMAIL" ]] && command -v mail &>/dev/null; then
        echo "$body" | mail -s "$subject" "$ALERT_EMAIL"
        log "INFO" "Alert email sent to $ALERT_EMAIL"
    fi
}

# =============================================================================
# Run the backup
# Creates a timestamped folder and rsyncs each source directory into it.
# =============================================================================
run_backup() {
    local timestamp
    timestamp=$(date "+%Y-%m-%d_%H-%M-%S")
    local snapshot_dir="$BACKUP_DEST/snapshot_$timestamp"

    log "INFO" "====== Backup started ======"
    log "INFO" "Snapshot destination: $snapshot_dir"

    mkdir -p "$snapshot_dir"

    local success=true

    for source in "${BACKUP_SOURCES[@]}"; do
        if [[ ! -e "$source" ]]; then
            log "WARN" "Source not found, skipping: $source"
            continue
        fi

        log "INFO" "Backing up: $source"

        # rsync flags explained:
        #   -a  archive mode (preserves permissions, timestamps, symlinks, etc.)
        #   -v  verbose — shows what's being copied
        #   -z  compress during transfer (helps if destination is remote later)
        #   --delete  remove files in the backup that no longer exist in source
        rsync -avz --delete \
            --exclude="*.tmp" \
            --exclude="*.pid" \
            --exclude="*.sock" \
            --log-file="$LOG_FILE" \
            "$source" "$snapshot_dir/" 2>&1

        if [[ $? -ne 0 ]]; then
            log "ERROR" "rsync failed for: $source"
            success=false
        else
            log "INFO" "Done: $source"
        fi
    done

    # Write a simple summary file inside the snapshot folder
    {
        echo "Backup created: $timestamp"
        echo "Sources:"
        for src in "${BACKUP_SOURCES[@]}"; do
            echo "  - $src"
        done
        echo "Status: $([ "$success" = true ] && echo 'OK' || echo 'PARTIAL FAILURE')"
        echo "Disk usage: $(du -sh "$snapshot_dir" 2>/dev/null | cut -f1)"
    } > "$snapshot_dir/BACKUP_INFO.txt"

    if [[ "$success" = true ]]; then
        log "INFO" "Backup completed successfully → $snapshot_dir"
    else
        log "ERROR" "Backup finished with errors — check the log for details"
        send_alert \
            "[ALERT] Backup failed on $(hostname)" \
            "One or more sources failed to back up at $timestamp. Check $LOG_FILE for details."
    fi
}

# =============================================================================
# Clean up old snapshots
# Deletes any snapshot folder older than RETENTION_DAYS days
# =============================================================================
cleanup_old_backups() {
    log "INFO" "Cleaning up backups older than $RETENTION_DAYS days..."

    local deleted=0

    while IFS= read -r -d '' old_dir; do
        rm -rf "$old_dir"
        log "INFO" "Removed old snapshot: $old_dir"
        ((deleted++))
    done < <(find "$BACKUP_DEST" -maxdepth 1 -type d -name "snapshot_*" \
              -mtime +$RETENTION_DAYS -print0)

    if [[ $deleted -eq 0 ]]; then
        log "INFO" "No old backups to clean up"
    else
        log "INFO" "Removed $deleted old snapshot(s)"
    fi
}

# =============================================================================
# List existing snapshots with their sizes and dates
# =============================================================================
list_backups() {
    echo ""
    echo "Available snapshots in $BACKUP_DEST:"
    echo ""

    if [[ -z "$(ls -A "$BACKUP_DEST" 2>/dev/null)" ]]; then
        echo "  No snapshots found yet."
    else
        printf "%-40s %-15s %s\n" "SNAPSHOT" "SIZE" "CREATED"
        printf "%-40s %-15s %s\n" "--------" "----" "-------"
        for dir in "$BACKUP_DEST"/snapshot_*/; do
            [[ -d "$dir" ]] || continue
            local name size created
            name=$(basename "$dir")
            size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            created=$(stat --format="%y" "$dir" 2>/dev/null | cut -d'.' -f1)
            printf "%-40s %-15s %s\n" "$name" "$size" "$created"
        done
    fi
    echo ""
}

# =============================================================================
# Restore from a specific snapshot
# Usage: ./backup.sh restore <snapshot_name> <destination>
# Example: ./backup.sh restore snapshot_2025-06-01_02-00-00 /tmp/restore-test
# =============================================================================
restore_backup() {
    local snapshot_name="$1"
    local restore_dest="$2"

    if [[ -z "$snapshot_name" || -z "$restore_dest" ]]; then
        log "ERROR" "Usage: $0 restore <snapshot_name> <destination_path>"
        return 1
    fi

    local snapshot_path="$BACKUP_DEST/$snapshot_name"

    if [[ ! -d "$snapshot_path" ]]; then
        log "ERROR" "Snapshot not found: $snapshot_path"
        return 1
    fi

    mkdir -p "$restore_dest"
    log "INFO" "Restoring $snapshot_name → $restore_dest"
    rsync -av "$snapshot_path/" "$restore_dest/"

    if [[ $? -eq 0 ]]; then
        log "INFO" "Restore complete → $restore_dest"
    else
        log "ERROR" "Restore failed — check the log"
        return 1
    fi
}

# =============================================================================
# Main
# =============================================================================
main() {
    local action="${1:-backup}"

    case "$action" in
        backup)
            run_backup
            cleanup_old_backups
            ;;
        cleanup)
            cleanup_old_backups
            ;;
        list)
            list_backups
            ;;
        restore)
            restore_backup "$2" "$3"
            ;;
        *)
            echo ""
            echo "Usage: $0 <action> [options]"
            echo ""
            echo "  backup                           — run a full backup (default)"
            echo "  list                             — show all snapshots"
            echo "  cleanup                          — delete snapshots older than ${RETENTION_DAYS} days"
            echo "  restore <snapshot> <destination> — restore a snapshot to a path"
            echo ""
            ;;
    esac
}

main "$@"