# `install/migrations/`

This directory contains **upgrade migrations** for Shadow Sentinel installations.

Migrations allow Shadow Sentinel to evolve (new configuration options, renamed settings, improved scheduling defaults, etc.) while keeping existing installs **safe, compatible, and non-destructive**.

In other words: this folder prevents "upgrade = reinstall from scratch".

---

## Why migrations exist

Users typically customize:

* `/etc/shadow-sentinel/shadow-sentinel.conf`
* scheduling (cron jobs or systemd timers)
* log paths / retention settings
* remote sync targets

When new versions are released, we **must not overwrite** user configuration or silently break existing behavior.

Migrations provide a controlled way to:

✅ add new settings with defaults  
✅ rename / deprecate old settings  
✅ update scheduling mechanisms (cron ↔ systemd)  
✅ modify paths, permissions, or runtime structure safely  
✅ apply fixes automatically during upgrades

---

## How migrations work

Each migration is a standalone script that performs a small, well-defined upgrade step.

Migrations are:

* **Ordered** (run in ascending order)
* **Idempotent** (safe to run multiple times)
* **Non-destructive** (never delete user config)
* **Auditable** (log their actions)

---

## Naming conventions

Migration files follow this naming format:

```
NNNN-short-description.sh
```

Examples:

* `0001-init.sh`
* `0002-retention-tiered.sh`
* `0003-remote-sync-split.sh`
* `0004-systemd-default.sh`

The numeric prefix ensures migrations always execute in the correct order.

---

## What a migration is allowed to change

Migrations may:

* edit the config file by **appending new settings**
* comment out deprecated settings instead of removing them
* create missing directories under `/var/lib/` or `/var/log/`
* install/update cron or systemd templates
* update state/metadata used by the installer

Migrations should **never**:

❌ overwrite the entire config  
❌ destroy existing snapshots  
❌ silently change backup semantics  without an explicit versioned step  
❌ require interactive input

---

## State tracking

Applied migrations are tracked using a state file, typically:

```
/var/lib/shadow-sentinel/migration-state.env
```

Example:

```c
LAST_MIGRATION=0003
```

On upgrades, the installer will:

1. detect the current migration level
2. run any new migrations in order
3. update the migration state file

---

## Writing a new migration

Keep migrations focused and minimal.

A good migration script should:

* validate prerequisites (config exists, required keys present, etc.)
* detect whether the change is needed (avoid duplicating work)
* log what it did
* exit successfully if no action is required

Example pattern:

```bash
if grep -q '^OLD_SETTING=' "$CONFIG" && ! grep -q '^NEW_SETTING=' "$CONFIG"; then
  # migrate old -new
fi
```

---

## Testing migrations

Before merging a new migration:

* test on a fresh install
* test on an older config with real customization
* test running the migration **twice**
* test in both cron and systemd environments (if applicable)

<br>
