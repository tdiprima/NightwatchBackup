# Scheduling Guide

Nightwatch Backup supports multiple scheduling methods. This guide covers setup and customization for systemd timers and cron.

## Scheduling Methods

Nightwatch Backup can be scheduled using:

1. **systemd timers** (recommended for modern Linux systems)
2. **cron** (traditional, universal compatibility)

The installer prompts you to choose during installation. You can switch methods later.

## systemd Timer (Recommended)

### Overview

systemd timers provide:

- Persistent scheduling (catches up missed runs)
- Randomized delays to avoid system load spikes
- Better logging integration
- Service dependency management

### Configuration Files

- Service unit: `/etc/systemd/system/nightwatch-backup.service`
- Timer unit: `/etc/systemd/system/nightwatch-backup.timer`

### Default Schedule

By default, backups run daily at **02:15 AM** with a **5-minute random delay**.

### View Timer Status

```bash
sudo systemctl status nightwatch-backup.timer
```

Or:

```bash
sudo ssctl status
```

### View Next Run Time

```bash
sudo systemctl list-timers nightwatch-backup.timer
```

### Customize Schedule

Edit the timer unit:

```bash
sudo systemctl edit --full nightwatch-backup.timer
```

#### Schedule Examples

**Daily at 3:00 AM:**

```ini
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
RandomizedDelaySec=300
```

**Every 6 hours:**

```ini
[Timer]
OnCalendar=00/6:00:00
Persistent=true
RandomizedDelaySec=300
```

**Twice daily (6 AM and 6 PM):**

```ini
[Timer]
OnCalendar=*-*-* 06,18:00:00
Persistent=true
RandomizedDelaySec=300
```

**Weekdays only at 11 PM:**

```ini
[Timer]
OnCalendar=Mon..Fri *-*-* 23:00:00
Persistent=true
RandomizedDelaySec=300
```

**Weekly on Sunday at 2 AM:**

```ini
[Timer]
OnCalendar=Sun *-*-* 02:00:00
Persistent=true
RandomizedDelaySec=600
```

#### OnCalendar Format

Format: `DayOfWeek Year-Month-Day Hour:Minute:Second`

Examples:

- `*-*-* 02:00:00` - Daily at 2 AM
- `Mon *-*-* 00:00:00` - Every Monday at midnight
- `*-*-01 00:00:00` - First day of every month at midnight
- `*-01,07 *-01 00:00:00` - January 1st and July 1st at midnight

### Apply Changes

After modifying the timer:

```bash
sudo systemctl daemon-reload
sudo systemctl restart nightwatch-backup.timer
```

### Disable/Enable Timer

Disable scheduled backups:

```bash
sudo systemctl stop nightwatch-backup.timer
sudo systemctl disable nightwatch-backup.timer
```

Enable scheduled backups:

```bash
sudo systemctl enable nightwatch-backup.timer
sudo systemctl start nightwatch-backup.timer
```

### Manual Trigger

Run backup immediately without waiting for schedule:

```bash
sudo systemctl start nightwatch-backup.service
```

Or:

```bash
sudo ssctl run
```

### View Logs

View systemd journal for backup runs:

```bash
sudo journalctl -u nightwatch-backup.service
```

Recent runs:

```bash
sudo journalctl -u nightwatch-backup.service -n 50
```

Follow logs in real-time:

```bash
sudo journalctl -u nightwatch-backup.service -f
```

## Cron

### Overview

Cron provides:

- Universal compatibility across Linux/Unix systems
- Simple, well-understood scheduling syntax
- Works on systems without systemd

### Configuration File

- Cron job: `/etc/cron.d/nightwatch-backup`

### Default Schedule

The default cron configuration is typically set during installation. You need to create or edit the file manually.

### View Current Cron Job

```bash
sudo cat /etc/cron.d/nightwatch-backup
```

### Edit Cron Schedule

```bash
sudo nano /etc/cron.d/nightwatch-backup
```

#### Cron Format

```
# minute hour day month weekday user command
```

#### Schedule Examples

**Daily at 2:15 AM:**

```cron
15 2 * * * root /usr/local/bin/nightwatch-backup run
```

**Every 6 hours:**

```cron
0 */6 * * * root /usr/local/bin/nightwatch-backup run
```

**Twice daily (6 AM and 6 PM):**

```cron
0 6,18 * * * root /usr/local/bin/nightwatch-backup run
```

**Weekdays at 11 PM:**

```cron
0 23 * * 1-5 root /usr/local/bin/nightwatch-backup run
```

**Weekly on Sunday at 2 AM:**

```cron
0 2 * * 0 root /usr/local/bin/nightwatch-backup run
```

**First day of month at midnight:**

```cron
0 0 1 * * root /usr/local/bin/nightwatch-backup run
```

#### Cron Syntax Reference

Field order:

1. Minute (0-59)
2. Hour (0-23)
3. Day of month (1-31)
4. Month (1-12)
5. Day of week (0-7, where 0 and 7 are Sunday)

Special characters:

- `*` - Any value
- `*/n` - Every n units
- `n-m` - Range from n to m
- `n,m` - Values n and m

### Add Random Delay

To avoid all servers backing up simultaneously:

```cron
15 2 * * * root sleep $((RANDOM \% 300)) && /usr/local/bin/nightwatch-backup run
```

This adds a random delay of 0-300 seconds (5 minutes).

### Cron Logs

View cron execution logs:

```bash
sudo grep nightwatch-backup /var/log/syslog
```

Or:

```bash
sudo journalctl -t CRON | grep nightwatch-backup
```

### Disable Cron Job

Comment out or remove the cron job:

```bash
sudo rm /etc/cron.d/nightwatch-backup
```

Or comment it out:

```cron
# 15 2 * * * root /usr/local/bin/nightwatch-backup run
```

## Switching Between Schedulers

### From Cron to systemd

1. Disable cron:

```bash
sudo rm /etc/cron.d/nightwatch-backup
```

2. Install systemd timer:

```bash
sudo cp install/templates/systemd/nightwatch-backup.service /etc/systemd/system/
sudo cp install/templates/systemd/nightwatch-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now nightwatch-backup.timer
```

### From systemd to Cron

1. Disable systemd timer:

```bash
sudo systemctl stop nightwatch-backup.timer
sudo systemctl disable nightwatch-backup.timer
```

2. Install cron job:

```bash
sudo cp install/templates/cron.d.template /etc/cron.d/nightwatch-backup
```

Edit as needed:

```bash
sudo nano /etc/cron.d/nightwatch-backup
```

## Best Practices

### Timing Considerations

1. **Off-peak hours**: Schedule during low-activity periods
2. **Before business hours**: Complete before users arrive
3. **Avoid overlaps**: Ensure backups finish before next run
4. **Random delays**: Prevent simultaneous backups across multiple systems

### Frequency Recommendations

| Use Case | Recommended Frequency |
|----------|----------------------|
| Production servers | Every 4-6 hours |
| Development servers | Daily |
| User workstations | Daily or twice daily |
| Critical databases | Every 1-2 hours |
| Archival systems | Weekly |

### Lock File Protection

Nightwatch Backup uses a lock file (`/var/lock/nightwatch-backup.lock`) to prevent concurrent runs:

- If a backup is running, new attempts will fail
- Lock is automatically removed on completion
- If system crashes, you may need to manually remove stale lock

Remove stale lock:

```bash
sudo rm /var/lock/nightwatch-backup.lock
```

### Monitoring

Set up monitoring to alert on:

- Failed backups (check exit codes)
- Missing backups (no new snapshots)
- Long-running backups
- Disk space issues

Example: Check for recent snapshot:

```bash
#!/bin/bash
LATEST=$(sudo nightwatch-backup list | head -n 1)
AGE=$(stat -c %Y "$LATEST")
NOW=$(date +%s)
HOURS=$(( (NOW - AGE) / 3600 ))

if [[ $HOURS -gt 24 ]]; then
  echo "WARNING: Latest backup is $HOURS hours old"
  exit 1
fi
```

## Troubleshooting

### Timer Not Running

Check timer status:

```bash
sudo systemctl status nightwatch-backup.timer
```

Check for errors:

```bash
sudo journalctl -u nightwatch-backup.timer -n 50
```

Restart timer:

```bash
sudo systemctl restart nightwatch-backup.timer
```

### Cron Not Executing

Check cron service:

```bash
sudo systemctl status cron
```

Check syntax:

```bash
sudo crontab -l
```

Verify file permissions:

```bash
ls -l /etc/cron.d/nightwatch-backup
```

Should be `-rw-r--r--` owned by root.

### Backups Running Too Long

If backups overlap:

1. Reduce backup frequency
2. Optimize sources (use excludes)
3. Check disk I/O performance
4. Consider incremental-only runs

## Next Steps

- Configure [retention policies](CONFIG.md#retention-policies)
- Set up [email notifications](CONFIG.md#email-notifications)
- Learn about [restore procedures](RESTORE.md)
- Review [troubleshooting tips](TROUBLESHOOTING.md)
