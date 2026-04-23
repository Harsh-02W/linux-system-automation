#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# create_user.sh — Provision a new user on the system
#
# Usage:
#   sudo bash create_user.sh <username> [group] [--no-password]
#
# Examples:
#   sudo bash create_user.sh alice
#   sudo bash create_user.sh bob developers
#   sudo bash create_user.sh carol interns --no-password
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Load config ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../config/settings.conf"
source "$CONFIG"

# ── Helpers ──────────────────────────────────────────────────────────────────
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_DIR/user-management.log"; }
die() { log "ERROR: $*"; exit 1; }

# ── Sanity checks ────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && die "Please run this script with sudo."
[[ $# -lt 1 ]]    && die "Usage: sudo bash create_user.sh <username> [group] [--no-password]"

USERNAME="$1"
GROUP="${2:-$DEFAULT_GROUP}"
NO_PASSWORD="${3:-}"

# Username must be lowercase letters, numbers, underscores, hyphens only
[[ "$USERNAME" =~ ^[a-z0-9_-]+$ ]] || die "Invalid username '$USERNAME'. Use only lowercase letters, numbers, _ or -"

# Don't accidentally overwrite an existing user
id "$USERNAME" &>/dev/null && die "User '$USERNAME' already exists."

mkdir -p "$LOG_DIR"

# ── Create group if it doesn't exist yet ─────────────────────────────────────
if ! getent group "$GROUP" &>/dev/null; then
    groupadd "$GROUP"
    log "Created group: $GROUP"
fi

# ── Create the user ──────────────────────────────────────────────────────────
log "Creating user: $USERNAME (group: $GROUP, shell: $DEFAULT_SHELL)"

useradd \
    --create-home \
    --shell "$DEFAULT_SHELL" \
    --gid "$GROUP" \
    --comment "Provisioned by linux-system-automation" \
    "$USERNAME"

# ── Handle password ──────────────────────────────────────────────────────────
if [[ "$NO_PASSWORD" == "--no-password" ]]; then
    # Lock the account — useful for service accounts or SSH-key-only users
    passwd -l "$USERNAME"
    log "Account '$USERNAME' created with no password (locked). Use SSH keys to log in."
else
    # Auto-generate a strong random password
    TEMP_PASS=$(openssl rand -base64 "$PASSWORD_LENGTH" | tr -dc 'A-Za-z0-9!@#$' | head -c "$PASSWORD_LENGTH")
    echo "$USERNAME:$TEMP_PASS" | chpasswd
    # Force the user to change it on first login — good hygiene
    chage -d 0 "$USERNAME"
    log "Account '$USERNAME' created. Temporary password set (user must change on first login)."
    echo ""
    echo "  ┌─────────────────────────────────────────┐"
    echo "  │  New User Credentials (share securely!) │"
    echo "  │  Username : $USERNAME"
    printf "  │  Password : %s\n" "$TEMP_PASS"
    echo "  │  Note     : Password change required at first login"
    echo "  └─────────────────────────────────────────┘"
    echo ""
fi

# ── Set up SSH directory ──────────────────────────────────────────────────────
USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
mkdir -p "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"
touch "$USER_HOME/.ssh/authorized_keys"
chmod 600 "$USER_HOME/.ssh/authorized_keys"
chown -R "$USERNAME:$GROUP" "$USER_HOME/.ssh"

log "Done! User '$USERNAME' is ready to go."