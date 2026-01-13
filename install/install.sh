#!/usr/bin/env bash
set -Eeuo pipefail

APP="nightwatch-backup"
PREFIX="/usr/local"
BIN_DIR="${PREFIX}/bin"
ETC_DIR="/etc/nightwatch-backup"
STATE_DIR="/var/lib/nightwatch-backup"
LOG_DIR="/var/log/nightwatch-backup"

need_root() { [[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }; }

install_files() {
  install -d "$BIN_DIR" "$ETC_DIR" "$STATE_DIR" "$LOG_DIR"
  install -m 0755 "./bin/nightwatch-backup" "$BIN_DIR/nightwatch-backup"
  install -m 0755 "./bin/ssctl" "$BIN_DIR/ssctl" || true
  install -m 0644 "./install/templates/nightwatch-backup.conf.example" "$ETC_DIR/nightwatch-backup.conf" \
    || true
}

choose_scheduler() {
  echo "Pick scheduler:"
  echo "  1) systemd timer"
  echo "  2) cron"
  read -r -p "Choice [1/2]: " choice
  case "${choice:-1}" in
    1) setup_systemd;;
    2) setup_cron;;
    *) setup_systemd;;
  esac
}

setup_systemd() {
  install -d /etc/systemd/system
  install -m 0644 "./install/templates/systemd/nightwatch-backup.service" /etc/systemd/system/
  install -m 0644 "./install/templates/systemd/nightwatch-backup.timer" /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now nightwatch-backup.timer
  echo "✅ systemd timer enabled"
}

setup_cron() {
  install -m 0644 "./install/templates/cron.d.template" /etc/cron.d/nightwatch-backup
  echo "✅ cron installed at /etc/cron.d/nightwatch-backup"
}

run_pending_migrations() {
  local APP_ID="nightwatch-backup"

  local ETC_DIR="/etc/${APP_ID}"
  local CONFIG_FILE="${ETC_DIR}/${APP_ID}.conf"

  local STATE_DIR="/var/lib/${APP_ID}"
  local MIGRATION_STATE_FILE="${STATE_DIR}/migration-state.env"

  local MIGRATIONS_DIR="./install/migrations"

  mkdir -p "$STATE_DIR"

  # Find last migration applied
  local last_applied="0000"
  if [[ -f "$MIGRATION_STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$MIGRATION_STATE_FILE" || true
    last_applied="${LAST_MIGRATION:-0000}"
  fi

  echo
  echo "== NightwatchBackup: Migration Check =="
  echo "Config:    $CONFIG_FILE"
  echo "State:     $MIGRATION_STATE_FILE"
  echo "Last seen: $last_applied"
  echo

  # No config? Then this is likely a fresh install.
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "No existing config found (fresh install). Skipping migrations."
    return 0
  fi

  # No migrations directory? (dev packaging / partial install)
  if [[ ! -d "$MIGRATIONS_DIR" ]]; then
    echo "Migrations directory missing: $MIGRATIONS_DIR (skipping)"
    return 0
  fi

  # Run migrations in lexicographic order (NNNN-*.sh)
  local ran_any=0
  local m base
  while IFS= read -r -d '' m; do
    base="$(basename "$m")"

    # Only run numbered migrations
    if [[ ! "$base" =~ ^[0-9]{4}-.*\.sh$ ]]; then
      continue
    fi

    local id="${base:0:4}"

    # Only run migrations > last applied
    if [[ "$id" > "$last_applied" ]]; then
      ran_any=1
      echo "-> Applying migration: $base"

      chmod +x "$m" || true

      # Export helpful variables for migration scripts
      export APP_ID
      export ETC_DIR
      export CONFIG_FILE
      export STATE_DIR
      export MIGRATION_STATE_FILE

      # Run migration
      if "$m"; then
        # Write/update migration state only after success
        cat > "$MIGRATION_STATE_FILE" <<EOF
# NightwatchBackup migration state
LAST_MIGRATION=${id}
EOF
        last_applied="$id"
        echo "✅ Migration applied: $base"
      else
        echo "❌ Migration failed: $base"
        echo "Stopping upgrade to avoid partial/unsafe state."
        exit 1
      fi

      echo
    fi
  done < <(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -print0 | sort -z)

  if [[ "$ran_any" -eq 0 ]]; then
    echo "No pending migrations."
  else
    echo "All migrations applied. Current level: $last_applied"
  fi
}

main() {
  need_root
  install_files
  # If upgrading an existing install, migrate config/state
  # run_pending_migrations
  choose_scheduler
  echo
  echo "Done. Edit config:"
  echo "  /etc/nightwatch-backup/nightwatch-backup.conf"
  echo "Test run:"
  echo "  nightwatch-backup run"
}

main "$@"
