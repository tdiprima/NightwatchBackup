# Quick Start Guide

This guide will help you install and configure Nightwatch Backup quickly.

## Prerequisites

Nightwatch Backup requires the following:

- Bash 4.0 or later
- rsync
- sha256sum
- tar
- find
- Root or sudo access for installation

## Installation

### 1. Clone or Download

```bash
git clone https://github.com/tdiprima/nightwatch-backup.git
cd nightwatch-backup
```

### 2. Run the Installer

The installer must be run as root:

```bash
sudo ./install/install.sh
```

The installer will:

- Copy binaries to `/usr/local/bin/`
- Create configuration directory at `/etc/nightwatch-backup/`
- Create state directory at `/var/lib/nightwatch-backup/`
- Create log directory at `/var/log/nightwatch-backup/`
- Prompt you to choose a scheduler (systemd timer or cron)

### 3. Choose Scheduler

During installation, you'll be asked to choose between:

1. **systemd timer** (recommended for modern Linux systems)
   - Runs daily at 02:15 with a 5-minute random delay
   - Persistent (catches up if system was off)

2. **cron** (for systems without systemd)
   - Traditional cron-based scheduling

## Configuration

### Basic Configuration

Edit the main configuration file:

```bash
sudo nano /etc/nightwatch-backup/nightwatch-backup.conf
```

**Minimum required settings:**

```bash
# Identity
BACKUP_NAME="my-backup"

# Root directories
BACKUP_ROOT="/srv/backups"
SNAPSHOT_DIR="/srv/backups/snapshots"

# Sources (space-separated paths)
SOURCES="/etc /home /var/www"
```

### Configuration Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `BACKUP_NAME` | Unique name for this backup set | Required |
| `BACKUP_ROOT` | Root directory for backups | Required |
| `SNAPSHOT_DIR` | Directory to store snapshots | Required |
| `SOURCES` | Space-separated paths to backup | Required |
| `EXCLUDES_FILE` | Path to exclusion patterns file | None |
| `RETENTION_KEEP_LAST` | Number of snapshots to keep | 21 |

See [CONFIG.md](CONFIG.md) for detailed configuration options.

## First Run

### Test Your Configuration

Run a manual backup to test your configuration:

```bash
sudo nightwatch-backup run
```

Or using the control utility:

```bash
sudo ssctl run
```

### Monitor Progress

Watch the logs in real-time:

```bash
sudo ssctl logs
```

Or directly:

```bash
sudo tail -f /var/log/nightwatch-backup/nightwatch-backup.log
```

## Verify Installation

### Check Scheduler Status

For systemd:

```bash
sudo ssctl status
```

Or:

```bash
sudo systemctl status nightwatch-backup.timer
```

### List Backups

View existing snapshots:

```bash
sudo nightwatch-backup list
```

Or:

```bash
sudo ssctl list
```

### Verify a Snapshot

Check the integrity of a specific snapshot:

```bash
sudo nightwatch-backup verify /srv/backups/snapshots/my-backup-hostname-20260112T120000Z
```

## Basic Operations

### Run Manual Backup

```bash
sudo ssctl run
```

### List All Snapshots

```bash
sudo ssctl list
```

### View Logs

```bash
sudo ssctl logs
```

### Check Timer Status

```bash
sudo ssctl status
```

## Next Steps

- Configure [email notifications](CONFIG.md#email-notifications)
- Set up [remote sync](CONFIG.md#remote-sync)
- Customize [retention policies](CONFIG.md#retention-policies)
- Learn about [scheduling options](SCHEDULING.md)
- Understand [restore procedures](RESTORE.md)

## Quick Troubleshooting

### Backup Won't Start

Check for lock file:

```bash
ls -l /var/lock/nightwatch-backup.lock
```

Remove if stale:

```bash
sudo rm /var/lock/nightwatch-backup.lock
```

### Permission Errors

Ensure directories are writable:

```bash
sudo chown -R root:root /srv/backups
sudo chmod -R 755 /srv/backups
```

### View Errors

Check the log file:

```bash
sudo grep ERROR /var/log/nightwatch-backup/nightwatch-backup.log
```

For more troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
