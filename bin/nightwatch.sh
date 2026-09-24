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
#             4 verification/manifest failed, 5 hook failed

set -o nounset
set -o pipefail

NW_HERE="$(cd "$(dirname "$0")" && pwd -P)"
for _lib in "$NW_HERE/../lib/common.sh" "$NW_HERE/../lib/nightwatch/common.sh" "/usr/local/lib/nightwatch/common.sh"; do
    # shellcheck disable=SC1090
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
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
NW_LOG_FILE="$NW_LOG_DIR/nightwatch-$RUN_ID.log"
STATUS_FILE="$NW_STATE_DIR/last-run.status"

# ---------------------------------------------------------------------------
# Status file writer (consumed by nightwatchctl status). Values are %q-escaped
# so the file is safe to source even when paths contain spaces or quotes.
# ---------------------------------------------------------------------------
START_TS="$(nw_now)"
VERIFIED=no; MANIFEST_COUNT=0; FINALIZED=0; MANIFEST_NAME=""
write_status() {
    local result="$1" rc="$2"
    local tmp="$STATUS_FILE.tmp.$$"
    {
        printf 'RUN_ID=%q\n'            "$RUN_ID"
        printf 'RESULT=%q\n'            "$result"
        printf 'EXIT_CODE=%q\n'         "$rc"
        printf 'START=%q\n'             "$START_TS"
        printf 'END=%q\n'               "$(nw_now)"
        printf 'CONFIG=%q\n'            "$NW_CONFIG_LOADED"
        printf 'DESTINATION=%q\n'       "$DESTINATION"
        printf 'LOG=%q\n'               "$NW_LOG_FILE"
        printf 'VERIFIED=%q\n'          "$VERIFIED"
        printf 'FILES_IN_MANIFEST=%q\n' "$MANIFEST_COUNT"
        printf 'MANIFEST=%q\n'         "$MANIFEST_NAME"
        printf 'DRY_RUN=%q\n'           "$DRY_RUN"
    } > "$tmp" && mv -f "$tmp" "$STATUS_FILE"
}
finish() { write_status "$1" "$2"; FINALIZED=1; exit "$2"; }

# ---------------------------------------------------------------------------
# Locking (ARCH-1): destination-based lock from lib/common.sh, shared with
# nightwatchctl verify so verification never reads a destination mid-write.
# ---------------------------------------------------------------------------
cleanup() {
    local rc=$?
    nw_lock_release
    if [ "$rc" -ne 0 ] && [ "$FINALIZED" = 0 ]; then
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
[ -d "$DESTINATION" ] || mkdir -p "$DESTINATION" || nw_die "Cannot create destination: $DESTINATION"
[ -w "$DESTINATION" ] || nw_die "Destination not writable: $DESTINATION"
if ! nw_lock_acquire "$LOCK_TIMEOUT"; then
    nw_error "Destination is locked by another Nightwatch process (pid ${NW_LOCK_OWNER:-unknown}); exiting"
    finish "SKIPPED_LOCKED" 2
fi

if [ -n "$PRE_HOOK" ]; then
    nw_info "Running PRE_HOOK"
    bash -c "$PRE_HOOK" >>"$NW_LOG_FILE" 2>&1 || finish "FAILED_PRE_HOOK" 5
fi

# rsync options. -a preserves perms/times/symlinks; -H hardlinks; --partial for resumability.
RSYNC_OPTS=(-a -H --partial --numeric-ids --stats)
[ "$DELETE_EXTRANEOUS" = true ] && RSYNC_OPTS+=(--delete --delete-excluded)
[ "$DRY_RUN" = 1 ] && RSYNC_OPTS+=(--dry-run)
[ "$VERBOSE" = 1 ] && RSYNC_OPTS+=(-v --progress)
[ "${BANDWIDTH_LIMIT:-0}" != 0 ] && RSYNC_OPTS+=("--bwlimit=$BANDWIDTH_LIMIT")
# macOS extended attributes when the installed rsync supports them
if [ "$(nw_os)" = macos ] && rsync --help 2>&1 | grep -q -- '--xattrs'; then
    RSYNC_OPTS+=(-X)
fi
for ex in "${EXCLUDES[@]:-}"; do
    [ -n "$ex" ] && RSYNC_OPTS+=("--exclude=$ex")
done
[ "${#RSYNC_EXTRA_OPTS[@]}" -gt 0 ] && RSYNC_OPTS+=("${RSYNC_EXTRA_OPTS[@]}")

# Each source is mirrored to DESTINATION/<basename>/ (so /home/alice -> DEST/alice/).
# Retry on transient rsync codes: 10/11/12 (I/O, socket), 23 (partial), 30 (timeout), 35.
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
for i in "${!NW_SRC_ABS[@]}"; do
    dst="$NW_DEST_ABS/${NW_SRC_NAME[$i]}"
    [ "$DRY_RUN" = 1 ] || mkdir -p "$dst" || nw_die "Cannot create $dst"
    run_rsync "${NW_SRC_ABS[$i]}" "$dst" || OVERALL_RC=3
done
[ "$OVERALL_RC" -eq 0 ] || finish "FAILED_RSYNC" 3

if [ "$DRY_RUN" = 1 ]; then
    nw_info "Dry run complete"
    finish "DRY_RUN_OK" 0
fi

# ---------------------------------------------------------------------------
# SHA-256 manifest + immediate verification (ARCH-2).
# The candidate manifest is built and verified in a temp file. Only after it
# passes is it published by atomically replacing .nightwatch/CURRENT, which
# records the run ID and verification state. A failed run leaves the previous
# published manifest untouched.
# ---------------------------------------------------------------------------
if [ "$CHECKSUM_MANIFEST" = true ]; then
    mkdir -p "$NW_MANIFEST_DIR" || nw_die "Cannot create $NW_MANIFEST_DIR"
    MANIFEST_NAME="$RUN_ID.sha256"
    candidate="$NW_MANIFEST_DIR/$MANIFEST_NAME.candidate"
    hash_err="$NW_STATE_DIR/hash-errors-$RUN_ID.txt"
    : > "$hash_err"
    nw_info "Generating SHA-256 manifest"
    : > "$candidate" || nw_die "Cannot write $candidate"
    for name in "${NW_SRC_NAME[@]}"; do
        # NUL-safe walk; paths written relative to DESTINATION with sha256sum escaping.
        ( cd "$NW_DEST_ABS" && find "$name" -type f -print0 ) | while IFS= read -r -d '' f; do
            if h="$(nw_sha256 "$NW_DEST_ABS/$f")" && [ -n "$h" ]; then
                nw_manifest_encode "$f" "$h" || printf 'write %s\n' "$f" >> "$hash_err"
            else
                printf 'hash %s\n' "$f" >> "$hash_err"
            fi
        done >> "$candidate"
        st=("${PIPESTATUS[@]}")
        if [ "${st[0]}" -ne 0 ] || [ "${st[1]}" -ne 0 ]; then
            nw_error "Manifest generation failed for $name (find=${st[0]} loop=${st[1]})"
            rm -f "$candidate"; finish "FAILED_MANIFEST" 4
        fi
    done
    if [ -s "$hash_err" ]; then
        nw_error "Manifest incomplete: $(wc -l < "$hash_err" | tr -d ' ') file(s) could not be hashed (see $hash_err)"
        rm -f "$candidate"; finish "FAILED_MANIFEST" 4
    fi
    rm -f "$hash_err"
    MANIFEST_COUNT="$(wc -l < "$candidate" | tr -d ' ')"
    nw_info "Candidate manifest: $MANIFEST_COUNT files"

    if [ "$VERIFY" = true ]; then
        nw_info "Verifying candidate against source (SHA-256)"
        vfail=0; vskip=0; verr=0
        vfail_list="$NW_STATE_DIR/verify-failures-$RUN_ID.txt"; : > "$vfail_list"
        while IFS= read -r line || [ -n "$line" ]; do
            [ -z "$line" ] && continue
            nw_manifest_decode "$line"
            h="$NW_M_HASH"; rel="$NW_M_PATH"
            top="${rel%%/*}"; rest="${rel#*/}"
            [ "$top" = "$rel" ] && rest=""
            if ! idx="$(nw_src_index "$top")"; then
                printf 'NOSOURCE %s\n' "$rel" >> "$vfail_list"; verr=$((verr+1)); continue
            fi
            srcfile="${NW_SRC_ABS[$idx]}${rest:+/$rest}"
            if [ ! -f "$srcfile" ]; then
                vskip=$((vskip+1)); continue      # deleted at source after sync; not corruption
            fi
            if ! sh="$(nw_sha256 "$srcfile")" || [ -z "$sh" ]; then
                printf 'HASHERR  %s\n' "$rel" >> "$vfail_list"; verr=$((verr+1)); continue
            fi
            if [ "$sh" != "$h" ]; then
                printf 'MISMATCH %s\n' "$rel" >> "$vfail_list"; vfail=$((vfail+1))
            fi
        done < "$candidate"
        if [ "$vfail" -gt 0 ] || [ "$verr" -gt 0 ]; then
            nw_error "Verification FAILED: $vfail mismatch(es), $verr error(s) (see $vfail_list); manifest NOT published"
            rm -f "$candidate"; finish "FAILED_VERIFY" 4
        fi
        rm -f "$vfail_list"
        VERIFIED=yes
        [ "$vskip" -gt 0 ] && nw_warn "$vskip source file(s) vanished after sync; skipped in verification"
        nw_info "Verification OK"
    fi

    sync 2>/dev/null || true
    mv -f "$candidate" "$NW_MANIFEST_DIR/$MANIFEST_NAME" || nw_die "Cannot write manifest"
    nw_current_publish "$MANIFEST_NAME" "$RUN_ID" "$VERIFIED" || nw_die "Cannot publish $NW_CURRENT"
    nw_info "Published manifest $MANIFEST_NAME (verified=$VERIFIED)"
    # keep the newest KEEP_MANIFESTS manifests (names are our own RUN_ID.sha256 format)
    # shellcheck disable=SC2012
    ls -1t "$NW_MANIFEST_DIR"/*.sha256 2>/dev/null | tail -n +"$(( ${KEEP_MANIFESTS:-5} + 1 ))" | while IFS= read -r old; do rm -f "$old"; done
fi

if [ -n "$POST_HOOK" ]; then
    nw_info "Running POST_HOOK"
    bash -c "$POST_HOOK" >>"$NW_LOG_FILE" 2>&1 || nw_warn "POST_HOOK exited non-zero"
fi

if [ "${KEEP_LOGS_DAYS:-0}" -gt 0 ]; then
    find "$NW_LOG_DIR" -name 'nightwatch-*.log' -type f -mtime +"$KEEP_LOGS_DAYS" -delete 2>/dev/null || true
fi

nw_info "Backup complete in $(( $(nw_now) - START_TS ))s"
finish "OK" 0
