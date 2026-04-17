#!/bin/bash
# =============================================================================
# user_management.sh
# Automates creating, removing, and listing system users.
# Run it directly or call specific functions from other scripts.
# =============================================================================

# --- Where logs go ---
LOG_DIR="$(dirname "$0")/../logs"
LOG_FILE="$LOG_DIR/user_management.log"
mkdir -p "$LOG_DIR"

# --- Helpers ---

# Writes a timestamped line to both the terminal and the log file
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Checks whether the person running this script has root privileges
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script needs to run as root (try: sudo $0)"
        exit 1
    fi
}

# =============================================================================
# Create a new user
# Usage: create_user <username> <group> <shell>
# Example: create_user alice developers /bin/bash
# =============================================================================
create_user() {
    local username="$1"
    local group="${2:-users}"       # default group is "users" if not provided
    local shell="${3:-/bin/bash}"   # default shell is bash

    # Make sure a username was actually passed in
    if [[ -z "$username" ]]; then
        log "ERROR" "create_user: no username provided. Usage: create_user <username> [group] [shell]"
        return 1
    fi

    # Don't create the user if they already exist
    if id "$username" &>/dev/null; then
        log "WARN" "User '$username' already exists — skipping creation"
        return 0
    fi

    # Create the group if it doesn't exist yet
    if ! getent group "$group" &>/dev/null; then
        log "INFO" "Group '$group' not found — creating it"
        groupadd "$group"
    fi

    # Create the user with a home directory
    useradd \
        --create-home \
        --gid "$group" \
        --shell "$shell" \
        --comment "Provisioned by user_management.sh" \
        "$username"

    if [[ $? -eq 0 ]]; then
        log "INFO" "Created user '$username' (group: $group, shell: $shell)"

        # Set a temporary password that expires immediately —
        # the user will be forced to change it on first login
        echo "$username:ChangeMe@123" | chpasswd
        passwd --expire "$username" &>/dev/null
        log "INFO" "Temporary password set for '$username' — will expire on first login"
    else
        log "ERROR" "Failed to create user '$username'"
        return 1
    fi
}

# =============================================================================
# Remove an existing user
# Usage: remove_user <username>
# The user's home directory is archived to /var/backups/ before deletion.
# =============================================================================
remove_user() {
    local username="$1"

    if [[ -z "$username" ]]; then
        log "ERROR" "remove_user: no username provided. Usage: remove_user <username>"
        return 1
    fi

    # Nothing to remove if the user doesn't exist
    if ! id "$username" &>/dev/null; then
        log "WARN" "User '$username' does not exist — nothing to remove"
        return 0
    fi

    # Back up the home directory before wiping it
    local home_dir
    home_dir=$(getent passwd "$username" | cut -d: -f6)

    if [[ -d "$home_dir" ]]; then
        local backup_path="/var/backups/${username}_home_$(date +%Y%m%d_%H%M%S).tar.gz"
        tar -czf "$backup_path" "$home_dir" 2>/dev/null
        log "INFO" "Home directory archived to: $backup_path"
    fi

    # Remove the user and their home directory
    userdel --remove "$username" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        log "INFO" "User '$username' removed successfully"
    else
        log "ERROR" "Failed to remove user '$username'"
        return 1
    fi
}

# =============================================================================
# List all non-system users (UID >= 1000)
# These are the real human accounts on the machine
# =============================================================================
list_users() {
    log "INFO" "Listing all regular user accounts (UID >= 1000):"
    echo ""
    printf "%-20s %-10s %-30s %-20s\n" "USERNAME" "UID" "HOME" "SHELL"
    printf "%-20s %-10s %-30s %-20s\n" "--------" "---" "----" "-----"

    while IFS=: read -r user _ uid _ _ home shell; do
        if [[ $uid -ge 1000 && $uid -lt 65534 ]]; then
            printf "%-20s %-10s %-30s %-20s\n" "$user" "$uid" "$home" "$shell"
        fi
    done < /etc/passwd

    echo ""
}

# =============================================================================
# Bulk provision users from a CSV file
# CSV format (no header): username,group,shell
# Example line: bob,developers,/bin/bash
# =============================================================================
bulk_create_users() {
    local csv_file="$1"

    if [[ -z "$csv_file" || ! -f "$csv_file" ]]; then
        log "ERROR" "bulk_create_users: CSV file not found. Usage: bulk_create_users <file.csv>"
        return 1
    fi

    log "INFO" "Starting bulk user provisioning from: $csv_file"

    local created=0
    local skipped=0
    local failed=0

    while IFS=',' read -r username group shell; do
        # Skip blank lines and comment lines (starting with #)
        [[ -z "$username" || "$username" == \#* ]] && continue

        if create_user "$username" "$group" "$shell"; then
            ((created++))
        else
            ((failed++))
        fi
    done < "$csv_file"

    log "INFO" "Bulk provisioning complete — Created: $created | Skipped: $skipped | Failed: $failed"
}

# =============================================================================
# Lock / Unlock a user account
# Useful for temporarily suspending access without deleting the account
# =============================================================================
lock_user() {
    local username="$1"
    if ! id "$username" &>/dev/null; then
        log "ERROR" "User '$username' not found"
        return 1
    fi
    usermod --lock "$username"
    log "INFO" "Account locked: $username"
}

unlock_user() {
    local username="$1"
    if ! id "$username" &>/dev/null; then
        log "ERROR" "User '$username' not found"
        return 1
    fi
    usermod --unlock "$username"
    log "INFO" "Account unlocked: $username"
}

# =============================================================================
# Main — run when the script is called directly (not sourced)
# =============================================================================
main() {
    require_root

    local action="${1:-list}"

    case "$action" in
        create)
            create_user "$2" "$3" "$4"
            ;;
        remove)
            remove_user "$2"
            ;;
        list)
            list_users
            ;;
        bulk)
            bulk_create_users "$2"
            ;;
        lock)
            lock_user "$2"
            ;;
        unlock)
            unlock_user "$2"
            ;;
        *)
            echo ""
            echo "Usage: sudo $0 <action> [options]"
            echo ""
            echo "  list                         — show all regular user accounts"
            echo "  create <user> [group] [shell] — create a single user"
            echo "  remove <user>                — archive home dir then delete user"
            echo "  bulk   <file.csv>            — provision many users from a CSV"
            echo "  lock   <user>                — temporarily disable an account"
            echo "  unlock <user>                — re-enable a locked account"
            echo ""
            ;;
    esac
}

main "$@"