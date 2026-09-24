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

# SHA-256 of a file; prints "<hash>" only. Hashes via stdin so the tool never
# prints (or escapes) the filename, and validates the result is 64 hex chars.
nw_sha256() {
    local h
    if command -v sha256sum >/dev/null 2>&1; then
        h="$(sha256sum < "$1" | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
        h="$(shasum -a 256 < "$1" | awk '{print $1}')"
    elif command -v openssl >/dev/null 2>&1; then
        h="$(openssl dgst -sha256 < "$1" | awk '{print $NF}')"
    else
        return 127
    fi || return 1
    case "$h" in
        [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) [ "${#h}" -eq 64 ] || return 1 ;;
        *) return 1 ;;
    esac
    printf '%s\n' "$h"
}

# Verify a checksum manifest (sha256sum format: "<hash>  <path>") from a dir.
# Prints failing paths; returns 0 if all ok.
nw_sha256_check() {
    local manifest="$1" base="$2" rc=0 hash path actual line
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        nw_manifest_decode "$line"
        hash="$NW_M_HASH"; path="$NW_M_PATH"
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
# Epoch -> local time string (BSD date -r, GNU date -d)
nw_date() { date -r "$1" +'%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$1" +'%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$1"; }

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
# Manifest path encoding (sha256sum convention): if a path contains a newline
# or backslash, the line is prefixed with "\" and the path has "\" -> "\\", NL -> "\n".
nw_manifest_encode() {
    local p="$1"
    case "$p" in
        *\\*|*$'\n'*)
            p="${p//\\/\\\\}"; p="${p//$'\n'/\\n}"
            printf '\\%s  %s\n' "$2" "$p" ;;
        *)  printf '%s  %s\n' "$2" "$p" ;;
    esac
}
# Parse one manifest line into NW_M_HASH / NW_M_PATH.
nw_manifest_decode() {
    local line="$1" esc=0
    case "$line" in \\*) esc=1; line="${line#\\}";; esac
    NW_M_HASH="${line%%  *}"
    NW_M_PATH="${line#*  }"
    if [ "$esc" = 1 ]; then
        local ph=$'\x01'
        NW_M_PATH="${NW_M_PATH//\\\\/$ph}"
        NW_M_PATH="${NW_M_PATH//\\n/$'\n'}"
        NW_M_PATH="${NW_M_PATH//$ph/\\}"
    fi
}

# True if $2 equals $1 or is inside directory $1 (both absolute).
nw_path_within() {
    local parent="${1%/}/" child="${2%/}/"
    [ "$parent" = "$child" ] || [ "${child#"$parent"}" != "$child" ]
}

# nw_load_config CONFIG [lenient]
#   lenient: skip checks that need the sources to be present (used by verify).
nw_load_config() {
    local cfg="${1:-$NW_CONFIG}" lenient="${2:-}"
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
    KEEP_MANIFESTS=5
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
    # Destination paths used by every command (lock, manifests) - resolved once.
    NW_DEST_ABS="$(nw_abspath "$DESTINATION" 2>/dev/null || printf '%s' "${DESTINATION%/}")"
    NW_META_DIR="$NW_DEST_ABS/.nightwatch"
    NW_LOCK_DIR="$NW_META_DIR/lock"
    NW_CURRENT="$NW_META_DIR/CURRENT"
    NW_MANIFEST_DIR="$NW_META_DIR/manifests"

    [ -n "$lenient" ] && return 0

    # ARCH-3: build the validated source->destination mapping once.
    # NW_SRC_ABS[i] = absolute source root, NW_SRC_NAME[i] = its dir name under DESTINATION.
    NW_SRC_ABS=(); NW_SRC_NAME=()
    local s a name seen=""
    for s in "${SOURCES[@]}"; do
        [ -d "$s" ] || nw_die "Config: source is not a directory: $s"
        a="$(nw_abspath "$s")"
        name="$(basename "$a")"
        [ "$a" = "/" ] && nw_die "Config: refusing to back up / as a source"
        case "$seen" in *"|$name|"*) nw_die "Config: two sources share the name '$name' and would overwrite each other in $DESTINATION";; esac
        seen="$seen|$name|"
        if nw_path_within "$a" "$NW_DEST_ABS"; then
            nw_die "Config: DESTINATION ($NW_DEST_ABS) is inside source $a (recursive backup)"
        fi
        if nw_path_within "$NW_DEST_ABS" "$a"; then
            nw_die "Config: source $a is inside DESTINATION ($NW_DEST_ABS)"
        fi
        NW_SRC_ABS+=("$a"); NW_SRC_NAME+=("$name")
    done
}

# Index into NW_SRC_* for a top-level destination name; prints index or returns 1.
nw_src_index() {
    local i
    for i in "${!NW_SRC_NAME[@]}"; do
        [ "${NW_SRC_NAME[$i]}" = "$1" ] && { printf '%s' "$i"; return 0; }
    done
    return 1
}

# ---------------------------------------------------------------------------
# ARCH-1: destination-based lock shared by every command that reads or writes
# the destination. mkdir is atomic on Linux and macOS; stale locks are reclaimed
# via an atomic rename so two reclaimers can never remove each other's lock.
#   nw_lock_acquire TIMEOUT   -> 0 acquired, 1 busy (owner pid in NW_LOCK_OWNER)
#   nw_lock_release
# ---------------------------------------------------------------------------
NW_HAVE_LOCK=0
NW_LOCK_OWNER=""
nw_lock_acquire() {
    local timeout="${1:-0}" waited=0 stale
    mkdir -p "$NW_META_DIR" 2>/dev/null || nw_die "Cannot create $NW_META_DIR"
    while ! mkdir "$NW_LOCK_DIR" 2>/dev/null; do
        NW_LOCK_OWNER="$(cat "$NW_LOCK_DIR/pid" 2>/dev/null || true)"
        if [ -n "$NW_LOCK_OWNER" ] && ! nw_pid_alive "$NW_LOCK_OWNER"; then
            stale="$NW_LOCK_DIR.stale.$$"
            if mv "$NW_LOCK_DIR" "$stale" 2>/dev/null; then
                nw_warn "Removed stale lock (pid $NW_LOCK_OWNER is dead)"
                rm -rf "$stale"
            fi
            continue
        fi
        if [ "$timeout" -gt 0 ] && [ "$waited" -lt "$timeout" ]; then
            sleep 5; waited=$((waited+5)); continue
        fi
        return 1
    done
    printf '%s\n' "$$" > "$NW_LOCK_DIR/pid"
    printf '%s\n' "$(hostname 2>/dev/null || echo ?) ${0##*/} $(nw_ts)" > "$NW_LOCK_DIR/info"
    NW_HAVE_LOCK=1
    return 0
}
nw_lock_release() {
    [ "$NW_HAVE_LOCK" = 1 ] && rm -rf "$NW_LOCK_DIR"
    NW_HAVE_LOCK=0
}

# ---------------------------------------------------------------------------
# ARCH-2: published manifest state. CURRENT is a %q key=value file that names
# the manifest file and records the run that produced it and whether it was
# verified. It is replaced with one atomic rename, so readers never see a
# manifest that has not passed verification.
# ---------------------------------------------------------------------------
nw_current_read() {
    MANIFEST=""; MANIFEST_RUN_ID=""; MANIFEST_VERIFIED=""; MANIFEST_TS=""
    [ -r "$NW_CURRENT" ] || return 1
    # shellcheck disable=SC1090
    . "$NW_CURRENT"
    [ -n "$MANIFEST" ] && [ -r "$NW_MANIFEST_DIR/$MANIFEST" ]
}
nw_current_publish() {   # MANIFEST_FILE_NAME RUN_ID VERIFIED
    local tmp="$NW_CURRENT.tmp.$$"
    {
        printf 'MANIFEST=%q\n' "$1"
        printf 'MANIFEST_RUN_ID=%q\n' "$2"
        printf 'MANIFEST_VERIFIED=%q\n' "$3"
        printf 'MANIFEST_TS=%q\n' "$(nw_now)"
    } > "$tmp" && mv -f "$tmp" "$NW_CURRENT" || return 1
    # Convenience symlink for humans / sha256sum -c; replaced atomically.
    ln -sfn "manifests/$1" "$NW_META_DIR/SHA256SUMS.tmp.$$" 2>/dev/null && mv -f "$NW_META_DIR/SHA256SUMS.tmp.$$" "$NW_META_DIR/SHA256SUMS" 2>/dev/null || true
    return 0
}
