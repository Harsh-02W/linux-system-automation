#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# bulk_provision.sh — Create multiple users from a CSV file
#
# CSV format (no header row):
#   username,group,full_name
#
# Example users.csv:
#   alice,developers,Alice Sharma
#   bob,interns,Bob Mehta
#   carol,developers,Carol Singh
#
# Usage:
#   sudo bash bulk_provision.sh users.csv
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../config/settings.conf"
source "$CONFIG"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_DIR/user-management.log"; }
die()  { log "ERROR: $*"; exit 1; }
info() { echo "  → $*"; }

[[ $EUID -ne 0 ]] && die "Please run this script with sudo."
[[ $# -lt 1 ]]    && die "Usage: sudo bash bulk_provision.sh <users.csv>"
[[ ! -f "$1" ]]   && die "File '$1' not found."

CSV_FILE="$1"
mkdir -p "$LOG_DIR"

# ── Count how many users we're about to create ───────────────────────────────
TOTAL=$(grep -c '.' "$CSV_FILE" || true)
log "Starting bulk provisioning — $TOTAL user(s) from '$CSV_FILE'"

CREATED=0
SKIPPED=0
FAILED=0

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Bulk User Provisioning"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

while IFS=',' read -r USERNAME GROUP FULL_NAME; do
    # Skip blank lines or comment lines
    [[ -z "$USERNAME" || "$USERNAME" == \#* ]] && continue

    USERNAME=$(echo "$USERNAME" | tr -d '[:space:]')
    GROUP=$(echo "$GROUP"       | tr -d '[:space:]')
    FULL_NAME=$(echo "$FULL_NAME" | sed 's/^[[:space:]]*//')

    echo ""
    echo "  Processing: $FULL_NAME ($USERNAME) → group: $GROUP"

    # Skip if user already exists
    if id "$USERNAME" &>/dev/null; then
        info "Skipped — '$USERNAME' already exists."
        log "SKIP: $USERNAME already exists."
        ((SKIPPED++))
        continue
    fi

    # Create group if needed
    if ! getent group "$GROUP" &>/dev/null; then
        groupadd "$GROUP" && info "Created group: $GROUP"
    fi

    # Create user
    if useradd --create-home --shell "$DEFAULT_SHELL" --gid "$GROUP" \
               --comment "$FULL_NAME" "$USERNAME" 2>>"$LOG_DIR/user-management.log"; then

        TEMP_PASS=$(openssl rand -base64 "$PASSWORD_LENGTH" | tr -dc 'A-Za-z0-9!@#$' | head -c "$PASSWORD_LENGTH")
        echo "$USERNAME:$TEMP_PASS" | chpasswd
        chage -d 0 "$USERNAME"  # Force password reset on first login

        info "Created ✓  |  Temp password: $TEMP_PASS"
        log "CREATED: $USERNAME ($FULL_NAME) in group $GROUP"
        ((CREATED++))
    else
        info "Failed ✗ — check logs for details."
        log "FAILED: Could not create $USERNAME"
        ((FAILED++))
    fi

done < "$CSV_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  Done! Created: %d  |  Skipped: %d  |  Failed: %d\n" "$CREATED" "$SKIPPED" "$FAILED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log "Bulk provisioning complete — Created: $CREATED, Skipped: $SKIPPED, Failed: $FAILED"