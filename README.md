# Nightwatch Backup

Configuration-driven rsync mirror for local folders. Bash only, runs on Linux and macOS.

- rsync mirror (`-aH --delete`), optional bandwidth limit and excludes
- Destination-based atomic `mkdir` lock shared by backup and verify, with stale-lock reclamation
- Retry on transient rsync errors (I/O, partial transfer, timeout)
- SHA-256 manifests under `DESTINATION/.nightwatch/manifests/`, published via an atomic `CURRENT` pointer that records run ID and verification state; `SHA256SUMS` symlink is `sha256sum -c` compatible
- Immediate post-run verification against the source; a manifest is only published after it passes, so a failed run leaves the previous verified manifest in place
- `nightwatchctl` controller: run, status, verify, logs, check, unlock, schedule
- Scheduling via systemd timer (Linux) or cron (Linux/macOS), rendered from templates in `scheduling/`

## Install

```sh
sudo ./install.sh                       # /usr/local, /etc/nightwatch/nightwatch.conf
sudo ./install.sh --prefix /opt/nightwatch --config /opt/nightwatch/nightwatch.conf
```

Edit the config, then:

```sh
sudo nightwatchctl check
sudo nightwatchctl run -n               # dry run
sudo nightwatchctl run
sudo nightwatchctl status
sudo nightwatchctl verify               # re-check destination against manifest
sudo nightwatchctl schedule enable      # systemd timer or cron, per platform
sudo nightwatchctl schedule render      # print rendered unit/cron for manual install
```

## Run without installing

```sh
NW_CONFIG=./my.conf NW_STATE_DIR=/tmp/nw/state NW_LOG_DIR=/tmp/nw/logs ./bin/nightwatchctl run
```

## Configuration

See `etc/nightwatch.conf.example`. Each source in `SOURCES` is mirrored to `DESTINATION/<basename>/`.

Validation rejects: duplicate source basenames, `/` as a source, a destination inside a source, and a source inside the destination.

`nightwatchctl verify` checks the destination against the published manifest only, so it works when the source disk is offline. It takes the destination lock, so it never overlaps a running backup.

## Exit codes

| Code | Meaning                         |
|------|---------------------------------|
| 0    | Success                         |
| 1    | Fatal / config error            |
| 2    | Another run holds the lock      |
| 3    | rsync failed after retries      |
| 4    | Manifest or verification failed |
| 5    | PRE_HOOK failed                 |

## Layout

```
bin/nightwatch.sh          backup engine
bin/nightwatchctl          controller CLI
lib/common.sh              shared functions (logging, sha256, config)
etc/nightwatch.conf.example
scheduling/                systemd unit + timer + cron templates (@PLACEHOLDER@ tokens, rendered by nightwatchctl)
install.sh
```

<br>
