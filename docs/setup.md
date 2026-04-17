# Setup Guide

This document walks you through deploying the Linux System Automation scripts on any Ubuntu/Debian machine from scratch.

## Prerequisites

Before running anything, make sure the following tools are installed:

```bash
# Update package lists
sudo apt update

# Install required tools
sudo apt install -y rsync cron

# Optional: install mailutils to enable email alerts
sudo apt install -y mailutils
```

Verify cron is running:

```bash
sudo systemctl status cron
```

If it's not active, start it:

```bash
sudo systemctl enable cron
sudo systemctl start cron
```

---

## Installation

Clone or copy the project to a stable location on your machine. `/opt` is recommended for system-level tools:

```bash
sudo cp -r linux-system-automation/ /opt/linux-system-automation
```

Make all scripts executable:

```bash
sudo chmod +x /opt/linux-system-automation/scripts/*.sh
```

Create the logs directory if it doesn't exist:

```bash
mkdir -p /opt/linux-system-automation/logs
```

---

## Configuring the Scripts

Each script has a configuration section near the top. Open the file and edit the variables to match your environment.

### backup.sh

```bash
BACKUP_SOURCES=("/etc" "/home" "/var/log")   # Directories to back up
BACKUP_DEST="/var/backups/system-snapshots"  # Where snapshots are stored
RETENTION_DAYS=7                             # Days to keep old snapshots
ALERT_EMAIL=""                               # Set to your email to get failure alerts
```

### health_monitor.sh

```bash
CPU_THRESHOLD=80        # Alert when CPU exceeds this percentage
MEM_THRESHOLD=85        # Alert when memory exceeds this percentage
DISK_THRESHOLD=90       # Alert when any disk partition exceeds this percentage

SERVICES_TO_CHECK=(
    "ssh"
    "cron"
    "rsyslog"
)
```

---

## Running the Scripts Manually

You can call any script directly to test it before scheduling it with cron.

```bash
# List all regular user accounts
sudo /opt/linux-system-automation/scripts/user_management.sh list

# Create a new user
sudo /opt/linux-system-automation/scripts/user_management.sh create alice developers /bin/bash

# Run a backup right now
/opt/linux-system-automation/scripts/backup.sh backup

# List all snapshots
/opt/linux-system-automation/scripts/backup.sh list

# Run a full health report
/opt/linux-system-automation/scripts/health_monitor.sh report

# Quick one-liner health check
/opt/linux-system-automation/scripts/health_monitor.sh quick
```

---

## Scheduling with Cron

Install the provided crontab to schedule everything automatically:

```bash
# Load the crontab for the current user
crontab /opt/linux-system-automation/cron/crontab.txt

# Verify it was installed
crontab -l
```

The default schedule is:

| Script | Schedule | What it does |
|---|---|---|
| backup.sh | Daily at 2:00 AM | Full backup + cleans up old snapshots |
| health_monitor.sh | Every 15 minutes | Writes a health report and alerts on issues |
| backup.sh cleanup | Sunday at 3:00 AM | Safety net cleanup of old backups |
| Log rotation | Daily at 4:00 AM | Compresses logs older than 7 days |

To change the schedule, edit `cron/crontab.txt` and reinstall with `crontab cron/crontab.txt`. Use [crontab.guru](https://crontab.guru) to test your expressions.

---

## Checking Logs

All scripts write to the `logs/` directory:

```bash
# Watch the health monitor log in real time
tail -f /opt/linux-system-automation/logs/health_monitor.log

# Read the latest health report
cat /opt/linux-system-automation/logs/health_report.txt

# Check cron job output
cat /opt/linux-system-automation/logs/cron.log
```

---

## Troubleshooting

**Script says "permission denied"**
Make sure it's executable: `sudo chmod +x scripts/your_script.sh`

**user_management.sh says it needs root**
Run it with sudo: `sudo ./scripts/user_management.sh list`

**Backup fails with rsync error**
Check that the source directories exist and the destination has write permissions.

**Cron job isn't running**
Verify cron is active (`sudo systemctl status cron`) and check that the paths in `crontab.txt` match your actual install location (`/opt/linux-system-automation/` by default).

**Email alerts not working**
Make sure `mailutils` is installed and your system's mail transport agent is configured. For simple testing, you can use `ssmtp` or `msmtp` with a Gmail relay.