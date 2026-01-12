# Restore Guide

This guide covers how to restore data from Nightwatch Backup backups.

## Understanding Snapshots

Nightwatch Backup creates timestamped snapshots with the following structure:

```c
/srv/backups/snapshots/
└── backup-name-hostname-20260112T120000Z/
    ├── MANIFEST.env          # Backup metadata
    ├── SHA256SUMS            # Checksums for verification
    └── data/                 # Mirrored source directory structure
        ├── etc/
        ├── home/
        └── var/
```

Each snapshot is a complete, browsable copy of your data at a specific point in time.

## Before Restoring

### 1. List Available Snapshots

```bash
sudo nightwatch-backup list
```

Or:

```bash
sudo ssctl list
```

Output example:

```
/srv/backups/snapshots/prod-core-server01-20260112T120000Z
/srv/backups/snapshots/prod-core-server01-20260111T120000Z
/srv/backups/snapshots/prod-core-server01-20260110T120000Z
```

### 2. Verify Snapshot Integrity

Before restoring, verify the snapshot hasn't been corrupted:

```bash
sudo nightwatch-backup verify /srv/backups/snapshots/prod-core-server01-20260112T120000Z
```

Or:

```bash
sudo ssctl verify /srv/backups/snapshots/prod-core-server01-20260112T120000Z
```

Successful output:

```sh
[INFO] Verification ok: /srv/backups/snapshots/prod-core-server01-20260112T120000Z
```

### 3. Examine Snapshot Contents

Browse the snapshot to locate your files:

```bash
ls -la /srv/backups/snapshots/prod-core-server01-20260112T120000Z/data/
```

The directory structure mirrors your source paths:

```bash
# View backed-up /etc files
ls /srv/backups/snapshots/prod-core-server01-20260112T120000Z/data/etc/

# View backed-up /home files
ls /srv/backups/snapshots/prod-core-server01-20260112T120000Z/data/home/
```

## Restore Methods

### Method 1: Restore Individual Files (Safest)

Copy specific files from the snapshot to their original location.

**Example: Restore a single configuration file**

```bash
sudo cp /srv/backups/snapshots/prod-core-server01-20260112T120000Z/data/etc/nginx/nginx.conf \
  /etc/nginx/nginx.conf
```

**Example: Restore a user's home directory**

```bash
sudo rsync -av \
  /srv/backups/snapshots/prod-core-server01-20260112T120000Z/data/home/username/ \
  /home/username/
```

### Method 2: Restore Entire Directory

Restore a complete directory tree.

**Example: Restore /etc directory**

```bash
sudo rsync -av \
  /srv/backups/snapshots/prod-core-server01-20260112T120000Z/data/etc/ \
  /etc/
```

**With dry-run first (recommended):**

```bash
# Preview what would be restored
sudo rsync -avn \
  /srv/backups/snapshots/prod-core-server01-20260112T120000Z/data/etc/ \
  /etc/

# If satisfied, run without -n
sudo rsync -av \
  /srv/backups/snapshots/prod-core-server01-20260112T120000Z/data/etc/ \
  /etc/
```

### Method 3: Restore with Excludes

Restore a directory while excluding certain paths.

```bash
sudo rsync -av \
  --exclude='*.log' \
  --exclude='cache/' \
  /srv/backups/snapshots/prod-core-server01-20260112T120000Z/data/var/www/ \
  /var/www/
```

### Method 4: Full System Restore

For disaster recovery, restore all backed-up paths.

**Step 1: Boot from live media or rescue system**

**Step 2: Mount target filesystem**

```bash
sudo mount /dev/sda1 /mnt
```

**Step 3: Restore data**

```bash
sudo rsync -aHAX --numeric-ids \
  /srv/backups/snapshots/prod-core-server01-20260112T120000Z/data/ \
  /mnt/
```

**Step 4: Reinstall bootloader**

```bash
sudo grub-install --root-directory=/mnt /dev/sda
sudo update-grub
```

**Step 5: Reboot**

```bash
sudo reboot
```

## Restore Scenarios

### Scenario 1: Accidental File Deletion

**Problem:** Accidentally deleted important file

**Solution:**

1. Find the file in latest snapshot:
```bash
SNAPSHOT=$(sudo nightwatch-backup list | head -n 1)
find "$SNAPSHOT/data" -name "important-file.txt"
```

2. Restore the file:
```bash
sudo cp "$SNAPSHOT/data/path/to/important-file.txt" /path/to/important-file.txt
```

### Scenario 2: Restore Previous Version

**Problem:** Need to restore file from 3 days ago

**Solution:**

1. Find snapshot from 3 days ago:

```bash
sudo nightwatch-backup list | grep "2026011[0-9]T"
```

2. Verify and restore:

```bash
SNAPSHOT="/srv/backups/snapshots/prod-core-server01-20260109T120000Z"
sudo nightwatch-backup verify "$SNAPSHOT"
sudo cp "$SNAPSHOT/data/path/to/file" /path/to/file
```

### Scenario 3: Configuration Rollback

**Problem:** New configuration broke the application

**Solution:**

1. Identify latest working snapshot (before change)
2. Restore configuration directory:

```bash
SNAPSHOT="/srv/backups/snapshots/prod-core-server01-20260111T120000Z"
sudo rsync -av "$SNAPSHOT/data/etc/myapp/" /etc/myapp/
```

3. Restart application:

```bash
sudo systemctl restart myapp
```

### Scenario 4: User Data Recovery

**Problem:** User needs deleted documents from last week

**Solution:**

1. Find snapshot from last week:

```bash
sudo nightwatch-backup list | grep "202601[0-9][0-9]T"
```

2. Let user browse and copy:

```bash
SNAPSHOT="/srv/backups/snapshots/prod-core-server01-20260105T120000Z"
sudo ls -la "$SNAPSHOT/data/home/username/Documents/"
sudo cp -r "$SNAPSHOT/data/home/username/Documents/deleted-project" \
  /home/username/Documents/
sudo chown -R username:username /home/username/Documents/deleted-project
```

### Scenario 5: Database Restore

**Problem:** Need to restore database files

**Solution:**

1. Stop database service:

```bash
sudo systemctl stop mysql
```

2. Restore database files:

```bash
SNAPSHOT="/srv/backups/snapshots/prod-core-server01-20260112T120000Z"
sudo rsync -av "$SNAPSHOT/data/var/lib/mysql/" /var/lib/mysql/
```

3. Fix permissions:

```bash
sudo chown -R mysql:mysql /var/lib/mysql
```

4. Start database:

```bash
sudo systemctl start mysql
```

## Advanced Restore Operations

### Selective Restore with Find

Find and restore all PHP files:

```bash
SNAPSHOT=$(sudo nightwatch-backup list | head -n 1)
cd "$SNAPSHOT/data/var/www"
find . -name "*.php" -exec cp --parents {} /var/www/ \;
```

### Restore Modified Files Only

Restore only files that differ from current system:

```bash
SNAPSHOT=$(sudo nightwatch-backup list | head -n 1)
sudo rsync -avc --update \
  "$SNAPSHOT/data/etc/" \
  /etc/
```

### Compare Snapshot to Current System

See what changed since backup:

```bash
SNAPSHOT=$(sudo nightwatch-backup list | head -n 1)
sudo diff -r "$SNAPSHOT/data/etc/" /etc/
```

Or with rsync:

```bash
sudo rsync -avcn --delete \
  "$SNAPSHOT/data/etc/" \
  /etc/
```

### Extract Files to Temporary Location

Restore to a different location for inspection:

```bash
SNAPSHOT=$(sudo nightwatch-backup list | head -n 1)
sudo rsync -av \
  "$SNAPSHOT/data/home/username/" \
  /tmp/restored-files/
```

## Working with Archives

If `ENABLE_TAR_ARCHIVE=1` was set, snapshots may also exist as tar archives.

### List Archive Contents

```bash
tar -tzf /srv/backups/snapshots/prod-core-server01-20260112T120000Z.tar.gz | less
```

### Extract Entire Archive

```bash
cd /tmp
tar -xzf /srv/backups/snapshots/prod-core-server01-20260112T120000Z.tar.gz
```

### Extract Specific Files

```bash
tar -xzf /srv/backups/snapshots/prod-core-server01-20260112T120000Z.tar.gz \
  data/etc/nginx/nginx.conf
```

## Remote Restore

If backups were synced to a remote server, you can restore from there.

### Pull Snapshot from Remote

```bash
sudo rsync -aHAX --numeric-ids \
  backupuser@backuphost:/data/nightwatch-backup/prod-core-server01-20260112T120000Z/ \
  /tmp/remote-snapshot/
```

### Direct Remote File Restore

```bash
sudo rsync -av \
  backupuser@backuphost:/data/nightwatch-backup/prod-core-server01-20260112T120000Z/data/etc/nginx/nginx.conf \
  /etc/nginx/nginx.conf
```

## Best Practices

### 1. Always Verify First

```bash
sudo nightwatch-backup verify <snapshot-path>
```

### 2. Use Dry-Run

Test restores with `-n` flag before actual restore:

```bash
sudo rsync -avn <source> <destination>
```

### 3. Backup Before Restore

Before overwriting current data, consider backing up current state:

```bash
sudo cp -a /etc/myapp /etc/myapp.before-restore
```

### 4. Check Permissions

After restore, verify file ownership and permissions:

```bash
ls -la /restored/path
sudo chown -R user:group /restored/path
```

### 5. Test After Restore

Always test that restored data works:

```bash
sudo systemctl restart myapp
sudo systemctl status myapp
```

### 6. Document Restores

Keep a log of what was restored and when:

```bash
echo "$(date): Restored /etc/nginx from snapshot 20260112T120000Z" | \
  sudo tee -a /var/log/restores.log
```

## Troubleshooting

### Permission Denied

Use `sudo` for all restore operations:

```bash
sudo rsync -av <source> <destination>
```

### Snapshot Not Found

List available snapshots:

```bash
sudo nightwatch-backup list
```

Check `SNAPSHOT_DIR` setting:

```bash
grep SNAPSHOT_DIR /etc/nightwatch-backup/nightwatch-backup.conf
```

### Verification Failed

If verification fails, the snapshot may be corrupted. Try an older snapshot:

```bash
sudo nightwatch-backup list
sudo nightwatch-backup verify <older-snapshot-path>
```

### Disk Space Issues

Check available space before restore:

```bash
df -h
```

Free space if needed:

```bash
sudo nightwatch-backup list | tail -n +15 | xargs sudo rm -rf
```

## Next Steps

- Set up [scheduled backups](SCHEDULING.md)
- Configure [retention policies](CONFIG.md#retention-policies)
- Review [troubleshooting guide](TROUBLESHOOTING.md)
