# Configuration Guide

This guide covers all configuration options for Nightwatch Backup.

## Configuration File Location

The main configuration file is located at:

```
/etc/nightwatch-backup/nightwatch-backup.conf
```

You can also specify a custom location using the `CONFIG_FILE` environment variable:

```bash
CONFIG_FILE=/path/to/config.conf nightwatch-backup run
```

## Required Settings

These settings must be configured before Nightwatch Backup can run:

### BACKUP_NAME

Unique identifier for this backup set.

```bash
BACKUP_NAME="prod-core"
```

- Used in snapshot directory naming
- Should be descriptive and unique per backup configuration
- Example: `prod-web`, `dev-database`, `home-laptop`

### BACKUP_ROOT

Root directory where backups are stored.

```bash
BACKUP_ROOT="/srv/backups"
```

- Must have sufficient disk space
- Recommend dedicated partition or volume
- Will be created if it doesn't exist

### SNAPSHOT_DIR

Directory where snapshots are stored (usually under `BACKUP_ROOT`).

```bash
SNAPSHOT_DIR="/srv/backups/snapshots"
```

- Each snapshot is a timestamped directory
- Will be created if it doesn't exist
- Can be on different mount point for performance

### SOURCES

Bash array of source directories to back up.

```bash
SOURCES=("/etc" "/home" "/var/www" "/opt/apps")
```

For paths with spaces, simply include them in the array:

```bash
SOURCES=("/etc" "/home/user/My Documents" "/var/www")
```

- Non-existent paths are skipped with warning
- Paths are preserved in snapshot structure

## Optional Settings

### Excludes

#### EXCLUDES_FILE

Path to a file containing rsync exclude patterns.

```bash
EXCLUDES_FILE="/etc/nightwatch-backup/excludes.txt"
```

Example `excludes.txt`:

```
*.tmp
*.cache
.git/
node_modules/
__pycache__/
*.log
/var/cache/
/tmp/
```

### Rsync Reliability

#### RSYNC_RETRIES

Number of retry attempts for failed rsync operations.

```bash
RSYNC_RETRIES=3
```

Default: `3`

#### RSYNC_RETRY_SLEEP

Seconds to wait between retry attempts.

```bash
RSYNC_RETRY_SLEEP=5
```

Default: `5`

### Verification

#### ENABLE_CHECKSUMS

Generate SHA256 checksums for all files in the snapshot.

```bash
ENABLE_CHECKSUMS=1  # 1=enabled, 0=disabled
```

Default: `1` (enabled)

- Creates `SHA256SUMS` file in snapshot root
- Useful for integrity verification
- Adds overhead to backup time

#### ENABLE_VERIFY

Verify checksums immediately after backup.

```bash
ENABLE_VERIFY=1  # 1=enabled, 0=disabled
```

Default: `1` (enabled)

- Checks all files against `SHA256SUMS`
- Fails backup if verification fails
- Provides immediate integrity confirmation

### Archive Packaging

#### ENABLE_TAR_ARCHIVE

Create a compressed tar archive of the snapshot.

```bash
ENABLE_TAR_ARCHIVE=0  # 1=enabled, 0=disabled
```

Default: `0` (disabled)

- Useful for off-site storage or archival
- Creates archive alongside snapshot directory
- Archive includes all files in the snapshot

#### TAR_COMPRESSION

Compression method for tar archives.

```bash
TAR_COMPRESSION="gzip"  # Options: gzip, zstd, none
```

Default: `gzip`

Options:

- `gzip` - Standard gzip compression (good compatibility)
- `zstd` - Zstandard compression (faster, better ratio)
- `none` - No compression (fastest)

#### TAR_EXT

File extension for tar archive.

```bash
TAR_EXT=".gz"
```

Default: `.gz`

Examples:

- `.gz` for gzip
- `.zst` for zstd
- `.tar` for none

### Retention Policies

#### RETENTION_KEEP_LAST

Number of recent snapshots to retain.

```bash
RETENTION_KEEP_LAST=21
```

Default: `21`

- Keeps the N most recent snapshots
- Older snapshots are automatically deleted
- Set to `0` to keep all snapshots (manual cleanup)

### Remote Sync

#### ENABLE_REMOTE_SYNC

Enable syncing snapshots to a remote server.

```bash
ENABLE_REMOTE_SYNC=0  # 1=enabled, 0=disabled
```

Default: `0` (disabled)

#### REMOTE_TARGET

Remote destination for snapshot sync.

```bash
REMOTE_TARGET="backupuser@backuphost:/data/nightwatch-backup"
```

Format: `user@host:/path`

- Requires SSH key-based authentication
- Remote path must exist and be writable
- Uses rsync over SSH

**Setup SSH keys:**

```bash
# Generate SSH key (if needed)
sudo ssh-keygen -t ed25519 -f /root/.ssh/nightwatch-backup

# Copy public key to remote server
sudo ssh-copy-id -i /root/.ssh/nightwatch-backup.pub backupuser@backuphost

# Test connection
sudo ssh -i /root/.ssh/nightwatch-backup backupuser@backuphost
```

### Email Notifications

#### ENABLE_EMAIL

Send email notifications after backup completion.

```bash
ENABLE_EMAIL=0  # 1=enabled, 0=disabled
```

Default: `0` (disabled)

#### EMAIL_TO

Email address for notifications.

```bash
EMAIL_TO="ops@example.com"
```

**Requirements:**

- Requires `mail` command (mailutils, mailx, or similar)
- System must be configured to send email (e.g., via sendmail, postfix, msmtp)

**Example msmtp setup:**

```bash
# Install msmtp
sudo apt-get install msmtp msmtp-mta

# Configure /etc/msmtprc
account default
host smtp.gmail.com
port 587
from backups@example.com
auth on
user backups@example.com
password your-app-password
tls on
tls_starttls on
```

## Environment Variables

You can override configuration paths using environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `CONFIG_FILE` | `/etc/nightwatch-backup/nightwatch-backup.conf` | Configuration file path |
| `STATE_DIR` | `/var/lib/nightwatch-backup` | State directory |
| `LOG_DIR` | `/var/log/nightwatch-backup` | Log directory |
| `LOG_FILE` | `$LOG_DIR/nightwatch-backup.log` | Log file path |
| `LOCK_FILE` | `/var/lock/nightwatch-backup.lock` | Lock file path |

Example:

```bash
CONFIG_FILE=/home/user/backup.conf nightwatch-backup run
```

## Configuration Examples

### Minimal Configuration

```bash
BACKUP_NAME="simple-backup"
BACKUP_ROOT="/backups"
SNAPSHOT_DIR="/backups/snapshots"
SOURCES=("/home/user/documents")
```

### Production Configuration

```bash
# Identity
BACKUP_NAME="prod-web-01"

# Paths
BACKUP_ROOT="/srv/backups"
SNAPSHOT_DIR="/srv/backups/snapshots"
SOURCES=("/etc" "/var/www" "/opt/apps" "/home")

# Excludes
EXCLUDES_FILE="/etc/nightwatch-backup/excludes.txt"

# Rsync reliability
RSYNC_RETRIES=5
RSYNC_RETRY_SLEEP=10

# Verification
ENABLE_CHECKSUMS=1
ENABLE_VERIFY=1

# Archive (for off-site storage)
ENABLE_TAR_ARCHIVE=1
TAR_COMPRESSION="zstd"
TAR_EXT=".zst"

# Retention (keep 30 days)
RETENTION_KEEP_LAST=30

# Remote sync
ENABLE_REMOTE_SYNC=1
REMOTE_TARGET="backup@offsite.example.com:/mnt/backups/prod-web-01"

# Notifications
ENABLE_EMAIL=1
EMAIL_TO="ops-team@example.com"
```

### Laptop/Desktop Configuration

```bash
# Identity
BACKUP_NAME="laptop-backup"

# Paths
BACKUP_ROOT="/mnt/external/backups"
SNAPSHOT_DIR="/mnt/external/backups/snapshots"
SOURCES=("/home/username")

# Excludes
EXCLUDES_FILE="/etc/nightwatch-backup/excludes.txt"

# Verification
ENABLE_CHECKSUMS=1
ENABLE_VERIFY=1

# Retention (keep 7 days)
RETENTION_KEEP_LAST=7

# Remote sync (to NAS)
ENABLE_REMOTE_SYNC=1
REMOTE_TARGET="user@nas.local:/volume1/backups"
```

## Validation

Nightwatch Backup validates configuration on startup. Common validation errors:

- **Missing required variables**: Set `BACKUP_NAME`, `BACKUP_ROOT`, `SNAPSHOT_DIR`, `SOURCES`
- **Missing commands**: Install `rsync`, `sha256sum`, `tar`, `find`
- **Directory creation failed**: Check permissions on parent directories
- **Invalid TAR_COMPRESSION**: Use `gzip`, `zstd`, or `none`

## Next Steps

- Set up [scheduling](SCHEDULING.md)
- Learn about [restore procedures](RESTORE.md)
- Review [troubleshooting](TROUBLESHOOTING.md)

<br>
