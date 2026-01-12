# Troubleshooting Guide

This guide covers common issues and their solutions for Nightwatch Backup.

## Quick Diagnostics

### Check Logs

View recent log entries:

```bash
sudo tail -n 100 /var/log/nightwatch-backup/nightwatch-backup.log
```

Follow logs in real-time:

```bash
sudo tail -f /var/log/nightwatch-backup/nightwatch-backup.log
```

Search for errors:

```bash
sudo grep ERROR /var/log/nightwatch-backup/nightwatch-backup.log
```

### Check Status

For systemd:

```bash
sudo systemctl status nightwatch-backup.timer
sudo systemctl status nightwatch-backup.service
```

Or:

```bash
sudo ssctl status
```

### Verify Configuration

Test configuration by running manually:

```bash
sudo nightwatch-backup run
```

## Common Issues

### 1. Lock File Exists

**Symptom:**

```
ERROR: Another run is active (lock: /var/lock/nightwatch-backup.lock holder: 12345)
```

**Cause:**

- Previous backup is still running
- Previous backup crashed leaving stale lock

**Solution:**

Check if process is actually running:

```bash
ps aux | grep nightwatch-backup
```

If no process exists, remove stale lock:

```bash
sudo rm /var/lock/nightwatch-backup.lock
```

If process exists and is hung:

```bash
sudo kill -9 <PID>
sudo rm /var/lock/nightwatch-backup.lock
```

**Prevention:**

- Ensure backups complete before next scheduled run
- Reduce backup frequency if runs take too long
- Optimize sources with excludes

### 2. Configuration File Not Found

**Symptom:**

```
ERROR: Missing config: /etc/nightwatch-backup/nightwatch-backup.conf
```

**Cause:**

Configuration file doesn't exist or wrong path.

**Solution:**

Check if file exists:

```bash
ls -l /etc/nightwatch-backup/nightwatch-backup.conf
```

Create from example:

```bash
sudo cp /etc/nightwatch-backup/nightwatch-backup.conf.example \
  /etc/nightwatch-backup/nightwatch-backup.conf
sudo nano /etc/nightwatch-backup/nightwatch-backup.conf
```

Or specify custom config:

```bash
CONFIG_FILE=/path/to/config.conf nightwatch-backup run
```

### 3. Missing Required Variables

**Symptom:**

```
ERROR: Must set BACKUP_NAME
ERROR: Must set SOURCES (space-separated paths)
```

**Cause:**

Required configuration variables not set.

**Solution:**

Edit configuration and add required variables:

```bash
sudo nano /etc/nightwatch-backup/nightwatch-backup.conf
```

Minimum required:

```bash
BACKUP_NAME="my-backup"
BACKUP_ROOT="/srv/backups"
SNAPSHOT_DIR="/srv/backups/snapshots"
SOURCES="/etc /home"
```

### 4. Missing Commands

**Symptom:**

```
ERROR: Missing required command: rsync
ERROR: Missing required command: sha256sum
```

**Cause:**

Required system utilities not installed.

**Solution:**

Install missing packages:

**Debian/Ubuntu:**

```bash
sudo apt-get update
sudo apt-get install rsync coreutils tar findutils
```

**RHEL/CentOS:**

```bash
sudo yum install rsync coreutils tar findutils
```

**Arch:**

```bash
sudo pacman -S rsync coreutils tar findutils
```

### 5. Permission Denied

**Symptom:**

```
ERROR: Unable to create snapshot dir: /srv/backups/snapshots/...
rsync: send_files failed to open "/etc/nightwatch": Permission denied
```

**Cause:**

Insufficient permissions to read sources or write to backup location.

**Solution:**

Run as root:

```bash
sudo nightwatch-backup run
```

Check backup directory permissions:

```bash
sudo ls -ld /srv/backups
sudo mkdir -p /srv/backups
sudo chown root:root /srv/backups
sudo chmod 755 /srv/backups
```

For source permission issues, ensure running as root or user with access.

### 6. Disk Space Issues

**Symptom:**

```
ERROR: No space left on device
rsync: write failed on "/srv/backups/...": No space left on device
```

**Cause:**

Insufficient disk space for backup.

**Solution:**

Check available space:

```bash
df -h /srv/backups
```

Free up space by:

1. Reducing retention:

```bash
# Edit config
sudo nano /etc/nightwatch-backup/nightwatch-backup.conf
# Set lower RETENTION_KEEP_LAST value
RETENTION_KEEP_LAST=7
```

2. Manually remove old snapshots:

```bash
sudo nightwatch-backup list
sudo rm -rf /srv/backups/snapshots/old-snapshot-name
```

3. Add exclusions to skip large unnecessary files:

```bash
sudo nano /etc/nightwatch-backup/excludes.txt
```

Add:

```
*.iso
*.img
*.tar.gz
/var/cache/
/tmp/
```

4. Move to larger volume:

```bash
# Edit config to point to larger mount
sudo nano /etc/nightwatch-backup/nightwatch-backup.conf
BACKUP_ROOT="/mnt/large-volume/backups"
SNAPSHOT_DIR="/mnt/large-volume/backups/snapshots"
```

### 7. Rsync Failures

**Symptom:**

```
ERROR: Rsync failed for source: /var/www
```

**Cause:**

Network issues, permission problems, or file system errors.

**Solution:**

Check source exists and is readable:

```bash
ls -la /var/www
```

Run rsync manually to diagnose:

```bash
sudo rsync -aHAX --numeric-ids /var/www /tmp/test-backup/
```

Increase retry attempts:

```bash
sudo nano /etc/nightwatch-backup/nightwatch-backup.conf
RSYNC_RETRIES=5
RSYNC_RETRY_SLEEP=10
```

### 8. Verification Failed

**Symptom:**

```
ERROR: Verification failed
sha256sum: WARNING: X computed checksums did NOT match
```

**Cause:**

Files changed during backup, disk errors, or corruption.

**Solution:**

Re-run backup:

```bash
sudo nightwatch-backup run
```

If persistent, check disk health:

```bash
sudo smartctl -a /dev/sda
sudo dmesg | grep -i error
```

Disable verification temporarily (not recommended):

```bash
sudo nano /etc/nightwatch-backup/nightwatch-backup.conf
ENABLE_VERIFY=0
```

### 9. Remote Sync Failures

**Symptom:**

```
ERROR: Remote sync failed
ssh: connect to host backuphost port 22: Connection refused
```

**Cause:**

Network issues, SSH authentication problems, or remote server down.

**Solution:**

Test SSH connection:

```bash
sudo ssh backupuser@backuphost
```

Setup SSH keys if needed:

```bash
sudo ssh-keygen -t ed25519 -f /root/.ssh/nightwatch-backup
sudo ssh-copy-id -i /root/.ssh/nightwatch-backup.pub backupuser@backuphost
```

Configure SSH config:

```bash
sudo nano /root/.ssh/config
```

Add:

```
Host backuphost
    HostName backuphost.example.com
    User backupuser
    IdentityFile /root/.ssh/nightwatch-backup
    StrictHostKeyChecking no
```

Test remote path writable:

```bash
sudo ssh backupuser@backuphost "touch /data/nightwatch-backup/test && rm /data/nightwatch-backup/test"
```

### 10. Email Notifications Not Working

**Symptom:**

Email notifications not received.

**Cause:**

Mail command not available or not configured.

**Solution:**

Check if mail command exists:

```bash
command -v mail
```

Install mail utility:

**Debian/Ubuntu:**

```bash
sudo apt-get install mailutils
```

**RHEL/CentOS:**

```bash
sudo yum install mailx
```

Test sending email:

```bash
echo "Test" | sudo mail -s "Test" your@email.com
```

Configure mail system (e.g., msmtp, postfix, sendmail).

### 11. Scheduled Backups Not Running

**Symptom:**

Backups are not running automatically.

**Cause:**

Timer/cron not enabled, misconfigured, or service not running.

**Solution:**

**For systemd:**

Check timer status:

```bash
sudo systemctl status nightwatch-backup.timer
```

Enable and start timer:

```bash
sudo systemctl enable nightwatch-backup.timer
sudo systemctl start nightwatch-backup.timer
```

View next scheduled run:

```bash
sudo systemctl list-timers nightwatch-backup.timer
```

**For cron:**

Check cron service:

```bash
sudo systemctl status cron
```

Verify cron job exists:

```bash
sudo cat /etc/cron.d/nightwatch-backup
```

Check cron logs:

```bash
sudo grep nightwatch-backup /var/log/syslog
```

### 12. Backup Takes Too Long

**Symptom:**

Backups take hours to complete or never finish.

**Cause:**

Too much data, slow disk, or network issues.

**Solution:**

1. Add exclusions for large unnecessary files:

```bash
sudo nano /etc/nightwatch-backup/excludes.txt
```

2. Check disk I/O:

```bash
sudo iotop
```

3. Reduce sources:

```bash
sudo nano /etc/nightwatch-backup/nightwatch-backup.conf
# Remove unnecessary paths from SOURCES
```

4. Check for hung processes:

```bash
ps aux | grep rsync
```

5. Schedule during off-peak hours (see [SCHEDULING.md](SCHEDULING.md))

### 13. Archive Creation Failed

**Symptom:**

```
ERROR: Tar failed
tar: Exiting with failure status due to previous errors
```

**Cause:**

Files changed during archiving, disk space, or permissions.

**Solution:**

Check disk space:

```bash
df -h
```

Disable archiving if not needed:

```bash
sudo nano /etc/nightwatch-backup/nightwatch-backup.conf
ENABLE_TAR_ARCHIVE=0
```

Or change compression method:

```bash
TAR_COMPRESSION="none"  # Faster, larger
```

### 14. Cannot Delete Old Snapshots

**Symptom:**

```
WARN: Failed to remove: /srv/backups/snapshots/old-snapshot
```

**Cause:**

Permission issues or mount point protection.

**Solution:**

Check permissions:

```bash
sudo ls -ld /srv/backups/snapshots/old-snapshot
```

Remove manually:

```bash
sudo rm -rf --one-file-system /srv/backups/snapshots/old-snapshot
```

Check if mounted:

```bash
mount | grep /srv/backups
```

## Advanced Debugging

### Enable Verbose Logging

Modify the script to add more logging (not recommended for production):

```bash
sudo nano /usr/local/bin/nightwatch-backup
```

Add `set -x` after shebang for verbose output.

### Run in Dry-Run Mode

Test configuration without actually performing backup:

Edit rsync commands to add `-n` flag for dry-run.

### Monitor System Resources

During backup:

```bash
# CPU and memory
top

# Disk I/O
sudo iotop

# Network
sudo nethogs

# Disk usage
watch -n 5 df -h
```

### Check File System Integrity

```bash
# Check for disk errors
sudo dmesg | grep -i error

# SMART status
sudo smartctl -a /dev/sda

# File system check (unmount first!)
sudo fsck /dev/sda1
```

## Log Analysis

### Find Failed Backups

```bash
sudo grep "ERROR" /var/log/nightwatch-backup/nightwatch-backup.log
```

### Find Specific Run ID

```bash
RUN_ID="20260112T120000Z-12345"
sudo grep "$RUN_ID" /var/log/nightwatch-backup/nightwatch-backup.log
```

### Count Backup Runs

```bash
sudo grep "Starting backup" /var/log/nightwatch-backup/nightwatch-backup.log | wc -l
```

### View Last Successful Backup

```bash
sudo grep "Run completed successfully" /var/log/nightwatch-backup/nightwatch-backup.log | tail -n 1
```

## Performance Optimization

### 1. Use Excludes Effectively

Exclude:

- Cache directories
- Temporary files
- Build artifacts
- Log files
- Virtual environments

### 2. Optimize Retention

Keep only necessary snapshots:

```bash
RETENTION_KEEP_LAST=14  # 2 weeks instead of 3
```

### 3. Disable Unnecessary Features

If not needed:

```bash
ENABLE_CHECKSUMS=0
ENABLE_TAR_ARCHIVE=0
ENABLE_REMOTE_SYNC=0
```

### 4. Use Faster Compression

For archives:

```bash
TAR_COMPRESSION="none"  # No compression
# OR
TAR_COMPRESSION="zstd"  # Faster than gzip
```

### 5. Schedule During Off-Peak Hours

See [SCHEDULING.md](SCHEDULING.md) for guidance.

## Getting Help

### Check Documentation

- [Quick Start Guide](QUICKSTART.md)
- [Configuration Guide](CONFIG.md)
- [Scheduling Guide](SCHEDULING.md)
- [Restore Guide](RESTORE.md)

### Collect Diagnostic Information

When reporting issues, include:

1. Nightwatch Backup version:

```bash
nightwatch-backup version
```

2. Configuration (redact sensitive info):

```bash
sudo cat /etc/nightwatch-backup/nightwatch-backup.conf
```

3. Recent logs:

```bash
sudo tail -n 200 /var/log/nightwatch-backup/nightwatch-backup.log
```

4. System info:

```bash
uname -a
df -h
free -h
```

5. Error messages (exact text)

## Emergency Recovery

### System Won't Boot After Restore

Boot from live media and check:

1. Bootloader configuration
2. `/etc/fstab` correctness
3. Kernel and initramfs present

Reinstall bootloader:

```bash
sudo mount /dev/sda1 /mnt
sudo grub-install --root-directory=/mnt /dev/sda
```

### Corrupted Backups

If latest backups are corrupted:

1. List all snapshots:

```bash
sudo nightwatch-backup list
```

2. Verify older snapshots:

```bash
sudo nightwatch-backup verify /srv/backups/snapshots/older-snapshot
```

3. Restore from oldest verified snapshot

4. Investigate disk/filesystem health

### Complete System Failure

If Nightwatch Backup system fails:

1. Backups are just directories - access them directly
2. Use any Linux system with rsync
3. Mount backup drive and copy files
4. No special tools needed for recovery
