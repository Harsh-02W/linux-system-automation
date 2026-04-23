# Linux System Automation

> Automated Bash scripts for user management, backups, monitoring, and log management — reducing manual sysadmin work by ~80%.

---

## Problem Statement

Manual system administration tasks are time-consuming and error-prone. This project automates the most common recurring sysadmin responsibilities using Bash scripts and cron jobs.

## Architecture Overview

```
linux-system-automation/
├── config/
│   └── settings.conf          # Central config — edit this first
├── user-management/
│   ├── create_user.sh         # Provision a single user
│   ├── delete_user.sh         # Safely remove a user (archives home first)
│   └── bulk_provision.sh      # Create many users from a CSV file
├── backup/
│   ├── backup_home.sh         # Daily compressed backup of /home
│   └── backup_logs.sh         # Weekly archive of critical system logs
├── monitoring/
│   ├── disk_check.sh          # Hourly disk usage check with alerts
│   ├── cpu_memory_check.sh    # 15-minute CPU/RAM monitoring
│   └── health_report.sh       # Daily full system health report
├── log-management/
│   ├── rotate_logs.sh         # Compress and rotate automation logs
│   └── cleanup_old_logs.sh    # Sweep stale logs from system directories
├── cron/
│   └── crontab_setup.sh       # One-time setup: registers all cron jobs
└── logs/                      # Runtime output from all scripts
```

## Prerequisites

| Requirement | Check |
|-------------|-------|
| Linux (Ubuntu/Debian recommended) | `uname -a` |
| Bash 4.0+ | `bash --version` |
| sudo / root access | `sudo whoami` |
| Standard utils: `tar`, `df`, `free`, `ps` | Pre-installed on Ubuntu |
| `bc` (for math) | `sudo apt install bc` |
| `mailutils` (optional, for email alerts) | `sudo apt install mailutils` |
| `rsync` (optional, for future use) | `sudo apt install rsync` |

## Quick Start

### 1. Clone the project

```bash
git clone https://github.com/yourusername/linux-system-automation.git
cd linux-system-automation
```

### 2. Edit the config

```bash
nano config/settings.conf
```

Key values to set:
- `BACKUP_DEST` — where backups should be stored
- `ALERT_EMAIL` — your email for alerts (optional)
- `DISK_THRESHOLD`, `CPU_THRESHOLD`, `MEM_THRESHOLD` — alert thresholds

### 3. Register all cron jobs

```bash
bash cron/crontab_setup.sh
```

That's it — the system is now automated.

---

## Script Reference

### User Management

```bash
# Create a single user
sudo bash user-management/create_user.sh alice developers

# Create a user with no password (SSH-key-only)
sudo bash user-management/create_user.sh deploy-bot --no-password

# Remove a user (archives home directory first)
sudo bash user-management/delete_user.sh alice

# Bulk provision from CSV
sudo bash user-management/bulk_provision.sh users.csv
```

**CSV format for bulk_provision.sh** (no header row):
```
alice,developers,Alice Sharma
bob,interns,Bob Mehta
carol,developers,Carol Singh
```

### Backup

```bash
# Run a backup manually
sudo bash backup/backup_home.sh

# Back up system logs manually
sudo bash backup/backup_logs.sh
```

### Monitoring

```bash
# Run a disk check now
bash monitoring/disk_check.sh

# Check CPU and memory
bash monitoring/cpu_memory_check.sh

# Generate a health report
bash monitoring/health_report.sh
```

### Log Management

```bash
# Rotate and compress logs
bash log-management/rotate_logs.sh

# Clean up old logs
bash log-management/cleanup_old_logs.sh
```

---

## Cron Schedule

| Schedule | Script |
|----------|--------|
| Every 15 minutes | `cpu_memory_check.sh` |
| Every hour | `disk_check.sh` |
| Daily at 2:00 AM | `backup_home.sh` |
| Daily at 7:00 AM | `health_report.sh` |
| Sunday at 3:00 AM | `backup_logs.sh` |
| Sunday at 4:00 AM | `rotate_logs.sh` |
| Sunday at 5:00 AM | `cleanup_old_logs.sh` |

View current cron jobs: `crontab -l`

---

## Outcomes

- ✅ Reduced manual intervention by ~80%
- ✅ Automated daily backups with 7-day retention
- ✅ Proactive alerts before disk/CPU/RAM issues become outages
- ✅ Auditable logs for every automated action
- ✅ Reusable, well-documented scripts for any Linux environment

---

## Tools & Technologies

`Linux` · `Bash` · `Cron` · `tar` · `df` · `free` · `ps` · `journalctl` · `useradd` · `openssl`

---

## Author

**Harsh** — DevOps Engineer  
[github.com/Harsh-02W](https://github.com/Harsh-02W)