#!/usr/bin/env bash
# Nightwatch Backup - rsync mirror engine with locking, retries, SHA-256 manifest,
# and immediate integrity verification. Linux + macOS.
#
# Usage: nightwatch.sh [-c CONFIG] [-n] [-q] [-v]
#   -c CONFIG   config file (default: $NW_CONFIG or /etc/nightwatch/nightwatch.conf)
#   -n          dry run (rsync --dry-run, no manifest, no verify)
#   -q          quiet (log file only, errors to stderr)
#   -v          verbose rsync output
#
# Exit codes: 0 ok, 1 fatal/config, 2 already running, 3 rsync failed after retries,
#             4 verification failed, 5 hook failed

set -o nounset
set -o pipefail

NW_HERE="$(cd "$(dirname "$0")" && pwd -P)"
for _lib in "$NW_HERE/../lib/common.sh" "$NW_HERE/../lib/nightwatch/common.sh" "/usr/local/lib/nightwatch/common.sh"; do
    if [ -r "$_lib" ]; then . "$_lib"; break; fi
done
command -v nw_log >/dev/null 2>&1 || { echo "nightwatch: cannot locate lib/common.sh" >&2; exit 1; }

DRY_RUN=0; VERBOSE=0
while getopts "c:nqvh" opt; do
    case "$opt" in
        c) NW_CONFIG="$OPTARG" ;;
        n) DRY_RUN=1 ;;
        q) NW_QUIET=1 ;;
        v) VERBOSE=1 ;;
        h) sed -n '2,15p' "$0"; exit 0 ;;
        *) exit 1 ;;
    esac
done

command -v rsync >/dev/null 2>&1 || nw_die "rsync not found in PATH"
nw_load_config "$NW_CONFIG"

mkdir -p "$NW_STATE_DIR" "$NW_LOG_DIR" 2>/dev/null || nw_die "Cannot create $NW_STATE_DIR / $NW_LOG_DIR"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
NW_LOG_FILE="$NW_LOG_DIR/nightwatch-$RUN_ID.log"
STATUS_FILE="$NW_STATE_DIR/last-run.status"
LOCK_DIR="$NW_STATE_DIR/nightwatch.lock"

# ---------------------------------------------------------------------------
# Status file writer (consumed by nightwatchctl status)
# ---------------------------------------------------------------------------
START_TS="$(nw_now)"
write_status() {
    local result="$1" rc="$2"
    local tmp="$STATUS_FILE.tmp.$$"
    {
        echo "RUN_ID=$RUN_ID"
        echo "RESULT=$result"
        echo "EXIT_CODE=$rc"
        echo "START=$START_TS"
        echo "END=$(nw_now)"
        echo "CONFIG=$NW_CONFIG_LOADED"
        echo "DESTINATION=$DESTINATION"
        echo "LOG=$NW_LOG_FILE"
        echo "VERIFIED=${VERIFIED:-no}"
        echo "FILES_IN_MANIFEST=${MANIFEST_COUNT:-0}"
        echo "DRY_RUN=$DRY_RUN"
    } > "$tmp" && mv -f "$tmp" "$STATUS_FILE"
}

# ---------------------------------------------------------------------------
# Locking: mkdir is atomic on both platforms (no flock on macOS by default)
# ---------------------------------------------------------------------------
acquire_lock() {
    local waited=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        local owner=""
        [ -r "$LOCK_DIR/pid" ] && owner="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
        if [ -n "$owner" ] && ! nw_pid_alive "$owner"; then
            nw_warn "Removing stale lock (pid $owner is dead)"
            rm -rf "$LOCK_DIR"
            continue
        fi
        if [ "$LOCK_TIMEOUT" -gt 0 ] && [ "$waited" -lt "$LOCK_TIMEOUT" ]; then
            sleep 5; waited=$((waited+5)); continue
        fi
        nw_error "Another Nightwatch run is active (pid ${owner:-unknown}); exiting"
        write_status "SKIPPED_LOCKED" 2
        exit 2
    done
    echo $$ > "$LOCK_DIR/pid"
    HAVE_LOCK=1
}
HAVE_LOCK=0
cleanup() {
    local rc=$?
    [ "$HAVE_LOCK" = 1 ] && rm -rf "$LOCK_DIR"
    if [ "$rc" -ne 0 ] && [ "${FINALIZED:-0}" = 0 ]; then
        write_status "FAILED" "$rc"
    fi
    exit "$rc"
}
trap cleanup EXIT
trap 'nw_error "Interrupted"; exit 130' INT TERM

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
nw_info "Nightwatch Backup v$NW_VERSION starting (run $RUN_ID, $(nw_os), pid $$)"
nw_info "Config: $NW_CONFIG_LOADED"
acquire_lock

[ -d "$DESTINATION" ] || mkdir -p "$DESTINATION" || nw_die "Cannot create destination: $DESTINATION"
[ -w "$DESTINATION" ] || nw_die "Destination not writable: $DESTINATION"

if [ -n "$PRE_HOOK" ]; then
    nw_info "Running PRE_HOOK"
    if ! bash -c "$PRE_HOOK" >>"$NW_LOG_FILE" 2>&1; then
        write_status "FAILED_PRE_HOOK" 5; FINALIZED=1; exit 5
    fi
fi

# rsync options. -a preserves perms/times/symlinks; -H hardlinks; --partial for resumability.
RSYNC_OPTS=(-a -H --partial --numeric-ids --stats)
[ "$DELETE_EXTRANEOUS" = true ] && RSYNC_OPTS+=(--delete --delete-excluded)
[ "$DRY_RUN" = 1 ] && RSYNC_OPTS+=(--dry-run)
[ "$VERBOSE" = 1 ] && RSYNC_OPTS+=(-v --progress) || RSYNC_OPTS+=(--info=progress0)
[ "${BANDWIDTH_LIMIT:-0}" != 0 ] && RSYNC_OPTS+=("--bwlimit=$BANDWIDTH_LIMIT")
# macOS extended attributes / resource forks when using Apple's or Homebrew rsync
if [ "$(nw_os)" = macos ] && rsync --help 2>&1 | grep -q -- '--xattrs'; then
    RSYNC_OPTS+=(-X)
fi
for ex in "${EXCLUDES[@]:-}"; do
    [ -n "$ex" ] && RSYNC_OPTS+=("--exclude=$ex")
done
[ "${#RSYNC_EXTRA_OPTS[@]}" -gt 0 ] && RSYNC_OPTS+=("${RSYNC_EXTRA_OPTS[@]}")

# Each source is mirrored to DESTINATION/<basename>/ (so /home/alice -> DEST/alice/).
# Retry on transient rsync codes: 10/11/12 (I/O, socket), 23/24 (partial, vanished), 30 (timeout), 35.
run_rsync() {
    local src="$1" dst="$2" attempt=1 rc
    while :; do
        nw_info "rsync [$attempt/$RETRIES] $src -> $dst"
        rsync "${RSYNC_OPTS[@]}" -- "$src/" "$dst/" >>"$NW_LOG_FILE" 2>&1
        rc=$?
        case "$rc" in
            0)  return 0 ;;
            24) nw_warn "rsync: some source files vanished during transfer (code 24), treating as success"; return 0 ;;
            10|11|12|23|30|35)
                if [ "$attempt" -ge "$RETRIES" ]; then
                    nw_error "rsync failed with code $rc after $attempt attempts"; return "$rc"
                fi
                nw_warn "rsync transient failure (code $rc); retrying in ${RETRY_DELAY}s"
                sleep "$RETRY_DELAY"; attempt=$((attempt+1)) ;;
            *)  nw_error "rsync failed with non-retryable code $rc"; return "$rc" ;;
        esac
    done
}

OVERALL_RC=0
for src in "${SOURCES[@]}"; do
    src="$(nw_abspath "$src")"
    name="$(basename "$src")"
    dst="$DESTINATION/$name"
    [ "$DRY_RUN" = 1 ] || mkdir -p "$dst"
    if ! run_rsync "$src" "$dst"; then
        OVERALL_RC=3
    fi
done

if [ "$OVERALL_RC" -ne 0 ]; then
    write_status "FAILED_RSYNC" 3; FINALIZED=1; exit 3
fi

if [ "$DRY_RUN" = 1 ]; then
    nw_info "Dry run complete"
    write_status "DRY_RUN_OK" 0; FINALIZED=1; exit 0
fi

# ---------------------------------------------------------------------------
# SHA-256 manifest + immediate verification
# ---------------------------------------------------------------------------
MANIFEST_COUNT=0
VERIFIED=no
if [ "$CHECKSUM_MANIFEST" = true ]; then
    MANIFEST="$DESTINATION/.nightwatch/SHA256SUMS"
    mkdir -p "$DESTINATION/.nightwatch"
    tmp_manifest="$MANIFEST.tmp.$$"
    nw_info "Generating SHA-256 manifest"
    : > "$tmp_manifest"
    for src in "${SOURCES[@]}"; do
        name="$(basename "$(nw_abspath "$src")")"
        # NUL-safe walk; paths written relative to DESTINATION.
        ( cd "$DESTINATION" && find "$name" -type f -print0 ) | while IFS= read -r -d '' f; do
            h="$(nw_sha256 "$DESTINATION/$f")" || { nw_error "hash failed: $f"; continue; }
            printf '%s  %s\n' "$h" "$f"
        done >> "$tmp_manifest"
    done
    mv -f "$tmp_manifest" "$MANIFEST"
    MANIFEST_COUNT="$(wc -l < "$MANIFEST" | tr -d ' ')"
    nw_info "Manifest written: $MANIFEST ($MANIFEST_COUNT files)"

    if [ "$VERIFY" = true ]; then
        nw_info "Verifying destination against source (SHA-256)"
        # Compare destination hash to a fresh source hash for each manifest entry.
        vfail=0; vfail_list="$NW_STATE_DIR/verify-failures-$RUN_ID.txt"; : > "$vfail_list"
        while IFS= read -r line || [ -n "$line" ]; do
            h="${line%% *}"; rel="${line#*  }"
            top="${rel%%/*}"; rest="${rel#*/}"
            [ "$top" = "$rel" ] && rest=""
            # locate source root matching this top-level name
            srcroot=""
            for s in "${SOURCES[@]}"; do
                [ "$(basename "$(nw_abspath "$s")")" = "$top" ] && { srcroot="$(nw_abspath "$s")"; break; }
            done
            [ -n "$srcroot" ] || continue
            srcfile="$srcroot${rest:+/$rest}"
            if [ ! -f "$srcfile" ]; then
                # Source changed since sync; not a corruption in the backup.
                continue
            fi
            sh="$(nw_sha256 "$srcfile")" || continue
            if [ "$sh" != "$h" ]; then
                printf '%s\n' "$rel" >> "$vfail_list"; vfail=$((vfail+1))
            fi
        done < "$MANIFEST"
        if [ "$vfail" -gt 0 ]; then
            nw_error "Verification FAILED: $vfail file(s) differ (see $vfail_list)"
            write_status "FAILED_VERIFY" 4; FINALIZED=1; exit 4
        fi
        rm -f "$vfail_list"
        VERIFIED=yes
        nw_info "Verification OK"
    fi
fi

if [ -n "$POST_HOOK" ]; then
    nw_info "Running POST_HOOK"
    bash -c "$POST_HOOK" >>"$NW_LOG_FILE" 2>&1 || nw_warn "POST_HOOK exited non-zero"
fi

# Log rotation
if [ "${KEEP_LOGS_DAYS:-0}" -gt 0 ]; then
    find "$NW_LOG_DIR" -name 'nightwatch-*.log' -type f -mtime +"$KEEP_LOGS_DAYS" -delete 2>/dev/null || true
fi

ELAPSED=$(( $(nw_now) - START_TS ))
nw_info "Backup complete in ${ELAPSED}s"
write_status "OK" 0; FINALIZED=1
exit 0
