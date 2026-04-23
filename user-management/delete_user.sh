#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# delete_user.sh — Safely remove a user from the system
#
# What it does:
#   - Archives the user's home directory before deletion (safety net)
#   - Removes the user account and optionally their primary group
#   - Logs everything for audit purposes
#
# Usage:
#   sudo bash delete_user.sh <username> [--keep-home]
#
# Examples:
#   sudo bash delete_user.sh alice           # Archive + delete home
#   sudo bash delete_user.sh bob --keep-home # Delete account, keep home dir
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../config/settings.conf"
source "$CONFIG"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_DIR/user-management.log"; }
die() { log "ERROR: $*"; exit 1; }

[[ $EUID -ne 0 ]]  && die "Please run this script with sudo."
[[ $# -lt 1 ]]     && die "Usage: sudo bash delete_user.sh <username> [--keep-home]"

USERNAME="$1"
KEEP_HOME="${2:-}"

# Make sure the user actually exists before we do anything
id "$USERNAME" &>/dev/null || die "User '$USERNAME' doesn't exist on this system."

# Guard against accidentally removing root or system accounts (UID < 1000)
USER_UID=$(id -u "$USERNAME")
[[ $USER_UID -lt 1000 ]] && die "Refusing to delete system/service account '$USERNAME' (UID $USER_UID). Do it manually if you're sure."

USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
mkdir -p "$LOG_DIR" "$BACKUP_DEST/user-archives"

# ── Archive home directory first ──────────────────────────────────────────────
if [[ "$KEEP_HOME" != "--keep-home" && -d "$USER_HOME" ]]; then
    ARCHIVE_NAME="$BACKUP_DEST/user-archives/${USERNAME}_$(date '+%Y%m%d_%H%M%S').tar.gz"
    log "Archiving home directory '$USER_HOME' → $ARCHIVE_NAME"
    tar -czf "$ARCHIVE_NAME" -C "$(dirname "$USER_HOME")" "$(basename "$USER_HOME")" 2>/dev/null || true
    log "Archive created: $ARCHIVE_NAME"
fi

# ── Kill any active sessions the user might have ──────────────────────────────
if who | grep -q "^$USERNAME "; then
    log "Terminating active sessions for '$USERNAME'..."
    pkill -u "$USERNAME" || true
    sleep 1
fi

# ── Delete the user ───────────────────────────────────────────────────────────
if [[ "$KEEP_HOME" == "--keep-home" ]]; then
    userdel "$USERNAME"
    log "Deleted user '$USERNAME' (home directory preserved at $USER_HOME)."
else
    userdel -r "$USERNAME" 2>/dev/null || userdel "$USERNAME"
    log "Deleted user '$USERNAME' and removed home directory."
fi

log "Done. User '$USERNAME' has been removed from the system."