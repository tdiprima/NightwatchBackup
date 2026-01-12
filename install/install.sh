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

main() {
  need_root
  install_files
  choose_scheduler
  echo
  echo "Done. Edit config:"
  echo "  /etc/nightwatch-backup/nightwatch-backup.conf"
  echo "Test run:"
  echo "  nightwatch-backup run"
}

main "$@"
