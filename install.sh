#!/usr/bin/env bash
# Nightwatch Backup installer (Linux + macOS)
# Usage: sudo ./install.sh [--prefix /usr/local] [--config /etc/nightwatch/nightwatch.conf] [--uninstall]
set -o nounset
set -o pipefail

PREFIX="/usr/local"
CONFIG="/etc/nightwatch/nightwatch.conf"
STATE_DIR="/var/lib/nightwatch"
LOG_DIR="/var/log/nightwatch"
UNINSTALL=0

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)    PREFIX="$2"; shift 2 ;;
        --config)    CONFIG="$2"; shift 2 ;;
        --state-dir) STATE_DIR="$2"; shift 2 ;;
        --log-dir)   LOG_DIR="$2"; shift 2 ;;
        --uninstall) UNINSTALL=1; shift ;;
        -h|--help)   sed -n '2,3p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

SRC="$(cd "$(dirname "$0")" && pwd -P)"
BIN="$PREFIX/bin"; LIB="$PREFIX/lib/nightwatch"; SHARE="$PREFIX/share/nightwatch"

if [ "$UNINSTALL" = 1 ]; then
    NW_CONFIG="$CONFIG" "$BIN/nightwatchctl" schedule disable 2>/dev/null || true
    rm -f "$BIN/nightwatch.sh" "$BIN/nightwatchctl"
    rm -rf "$LIB" "$SHARE"
    echo "Removed binaries and library. Kept config ($CONFIG), state ($STATE_DIR), logs ($LOG_DIR)."
    exit 0
fi

command -v rsync >/dev/null 2>&1 || { echo "rsync is required. Install it first (apt/dnf/brew install rsync)." >&2; exit 1; }
[ "${BASH_VERSINFO[0]}" -ge 3 ] || { echo "bash >= 3.2 required" >&2; exit 1; }

install -d -m 755 "$BIN" "$LIB" "$SHARE/scheduling" "$(dirname "$CONFIG")" "$STATE_DIR" "$LOG_DIR"
install -m 755 "$SRC/bin/nightwatch.sh" "$BIN/nightwatch.sh"
install -m 755 "$SRC/bin/nightwatchctl" "$BIN/nightwatchctl"
install -m 644 "$SRC/lib/common.sh"     "$LIB/common.sh"
install -m 644 "$SRC/scheduling/"*      "$SHARE/scheduling/"
install -m 644 "$SRC/etc/nightwatch.conf.example" "$SHARE/nightwatch.conf.example"

if [ ! -f "$CONFIG" ]; then
    install -m 600 "$SRC/etc/nightwatch.conf.example" "$CONFIG"
    echo "Created config: $CONFIG  (edit SOURCES and DESTINATION before running)"
else
    echo "Config exists, left untouched: $CONFIG"
fi

# Bake non-default paths into a small env wrapper if the user changed them.
if [ "$CONFIG" != "/etc/nightwatch/nightwatch.conf" ] || [ "$STATE_DIR" != "/var/lib/nightwatch" ] || [ "$LOG_DIR" != "/var/log/nightwatch" ]; then
    cat > "$LIB/env.sh" <<ENV
NW_CONFIG="\${NW_CONFIG:-$CONFIG}"
NW_STATE_DIR="\${NW_STATE_DIR:-$STATE_DIR}"
NW_LOG_DIR="\${NW_LOG_DIR:-$LOG_DIR}"
ENV
    # Prepend env sourcing into installed common.sh
    { echo ". \"$LIB/env.sh\""; cat "$SRC/lib/common.sh"; } > "$LIB/common.sh"
fi

echo "Installed:"
echo "  $BIN/nightwatch.sh"
echo "  $BIN/nightwatchctl"
echo "  $LIB/common.sh"
echo "  $SHARE/scheduling/{nightwatch.service,nightwatch.timer,nightwatch.cron}"
echo
echo "Next:"
echo "  1. Edit $CONFIG"
echo "  2. nightwatchctl check"
echo "  3. nightwatchctl run -n      # dry run"
echo "  4. nightwatchctl schedule enable"
