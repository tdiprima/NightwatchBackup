#!/usr/bin/env bash
# Nightwatch Backup - shared library (sourced by nightwatch.sh and nightwatchctl)
# Portable across Linux (GNU) and macOS (BSD) userlands. Requires bash >= 3.2.

NW_VERSION="1.0.0"

# ---------------------------------------------------------------------------
# Paths (overridable via environment)
# ---------------------------------------------------------------------------
NW_PREFIX="${NW_PREFIX:-/usr/local}"
NW_CONFIG="${NW_CONFIG:-/etc/nightwatch/nightwatch.conf}"
NW_STATE_DIR="${NW_STATE_DIR:-/var/lib/nightwatch}"
NW_LOG_DIR="${NW_LOG_DIR:-/var/log/nightwatch}"

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------
nw_os() {
    case "$(uname -s)" in
        Darwin) echo macos ;;
        Linux)  echo linux ;;
        *)      echo unknown ;;
    esac
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
NW_LOG_FILE="${NW_LOG_FILE:-}"
NW_QUIET="${NW_QUIET:-0}"

nw_ts() { date +"%Y-%m-%d %H:%M:%S"; }

nw_log() {
    local level="$1"; shift
    local line
    line="$(nw_ts) [$level] $*"
    if [ -n "$NW_LOG_FILE" ]; then
        printf '%s\n' "$line" >> "$NW_LOG_FILE" 2>/dev/null || true
    fi
    if [ "$NW_QUIET" != "1" ] || [ "$level" = "ERROR" ]; then
        if [ "$level" = "ERROR" ] || [ "$level" = "WARN" ]; then
            printf '%s\n' "$line" >&2
        else
            printf '%s\n' "$line"
        fi
    fi
}
nw_info()  { nw_log INFO  "$@"; }
nw_warn()  { nw_log WARN  "$@"; }
nw_error() { nw_log ERROR "$@"; }
nw_die()   { nw_error "$@"; exit 1; }

# ---------------------------------------------------------------------------
# Portable helpers
# ---------------------------------------------------------------------------

# SHA-256 of a file; prints "<hash>" only.
nw_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -- "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 -- "$1" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 -- "$1" | awk '{print $NF}'
    else
        return 127
    fi
}

# Verify a checksum manifest (sha256sum format: "<hash>  <path>") from a dir.
# Prints failing paths; returns 0 if all ok.
nw_sha256_check() {
    local manifest="$1" base="$2" rc=0 hash path actual
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        hash="${line%% *}"
        path="${line#*  }"
        if [ ! -f "$base/$path" ]; then
            printf 'MISSING  %s\n' "$path"; rc=1; continue
        fi
        actual="$(nw_sha256 "$base/$path")" || { printf 'ERROR    %s\n' "$path"; rc=1; continue; }
        if [ "$actual" != "$hash" ]; then
            printf 'MISMATCH %s\n' "$path"; rc=1
        fi
    done < "$manifest"
    return $rc
}

# Absolute path resolution (no readlink -f on macOS < 12.3)
nw_abspath() {
    local p="$1"
    if [ -d "$p" ]; then
        (cd "$p" 2>/dev/null && pwd -P)
    else
        local d; d="$(dirname "$p")"
        (cd "$d" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$(basename "$p")")
    fi
}

# Epoch seconds
nw_now() { date +%s; }

# Human-readable bytes
nw_human() {
    awk -v b="$1" 'BEGIN{
        split("B KB MB GB TB PB",u," "); i=1;
        while (b>=1024 && i<6){b/=1024;i++}
        printf (i==1?"%d %s":"%.1f %s"), b, u[i]}'
}

# Process alive?
nw_pid_alive() { kill -0 "$1" 2>/dev/null; }

# ---------------------------------------------------------------------------
# Config loading (sourced KEY=value shell file, validated afterward)
# ---------------------------------------------------------------------------
nw_load_config() {
    local cfg="${1:-$NW_CONFIG}"
    [ -r "$cfg" ] || nw_die "Config not readable: $cfg"
    # Defaults
    SOURCES=()
    DESTINATION=""
    EXCLUDES=()
    RSYNC_EXTRA_OPTS=()
    RETRIES=3
    RETRY_DELAY=30
    LOCK_TIMEOUT=0
    VERIFY=true
    CHECKSUM_MANIFEST=true
    DELETE_EXTRANEOUS=true
    KEEP_LOGS_DAYS=30
    BANDWIDTH_LIMIT=0
    PRE_HOOK=""
    POST_HOOK=""
    # shellcheck disable=SC1090
    . "$cfg"
    NW_CONFIG_LOADED="$cfg"

    # Validation
    [ "${#SOURCES[@]}" -gt 0 ] || nw_die "Config: SOURCES is empty"
    [ -n "$DESTINATION" ]      || nw_die "Config: DESTINATION is empty"
    case "$RETRIES" in ''|*[!0-9]*) nw_die "Config: RETRIES must be an integer";; esac
    case "$RETRY_DELAY" in ''|*[!0-9]*) nw_die "Config: RETRY_DELAY must be an integer";; esac
    case "$LOCK_TIMEOUT" in ''|*[!0-9]*) nw_die "Config: LOCK_TIMEOUT must be an integer";; esac
    local s
    for s in "${SOURCES[@]}"; do
        [ -d "$s" ] || nw_die "Config: source is not a directory: $s"
    done
}
