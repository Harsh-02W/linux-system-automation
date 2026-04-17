# Linux System Automation

A collection of Bash scripts that automate repetitive Linux system administration tasks — user management, backups, and health monitoring — and wire them together with cron for hands-off operation.

Built as a portfolio project to demonstrate practical Linux and DevOps skills.

---

## What It Does

| Script | Purpose |
|---|---|
| `user_management.sh` | Create, remove, lock, unlock, and bulk-provision system users |
| `backup.sh` | Snapshot directories with rsync, auto-clean old backups, restore from any snapshot |
| `health_monitor.sh` | Monitor CPU, memory, disk, and services — report and alert when thresholds are crossed |

Cron schedules everything to run automatically. All output is logged to the `logs/` directory.

---

## Project Structure

```
linux-system-automation/
├── scripts/
│   ├── user_management.sh   # User provisioning and account management
│   ├── backup.sh            # Backup, restore, and snapshot cleanup
│   └── health_monitor.sh    # System health checks and reporting
├── cron/
│   └── crontab.txt          # Ready-to-install cron schedule
├── logs/                    # Script output and health reports (git-ignored)
│   └── .gitkeep
├── docs/
│   └── setup.md             # Full installation and usage guide
└── README.md
```

---

## Quick Start

```bash
# 1. Clone the project
git clone <your-repo-url> linux-system-automation
cd linux-system-automation

# 2. Make scripts executable
chmod +x scripts/*.sh

# 3. Test a quick health check (no root needed)
./scripts/health_monitor.sh quick

# 4. Install the cron schedule
crontab cron/crontab.txt
```

See [docs/setup.md](docs/setup.md) for the full setup guide including configuration options.

---

## Tools & Technologies

- **Bash** — all automation logic
- **Cron** — scheduled execution
- **rsync** — efficient incremental backups
- **systemctl** — service health checks
- **/proc filesystem** — CPU and memory metrics
- **Linux user management tools** — `useradd`, `usermod`, `userdel`, `chpasswd`

---

## Outcomes

- Eliminated manual daily backup tasks
- System health checked automatically every 15 minutes
- New user accounts can be provisioned in bulk from a CSV in seconds
- All activity logged with timestamps for easy auditing