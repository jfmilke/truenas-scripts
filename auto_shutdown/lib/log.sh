#!/usr/bin/env bash
# Logging helpers. Everything is written to stdout/stderr; log_setup_file
# additionally tees it into LOG_FILE.

log()       { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
log_info()  { log "INFO  $*"; }
log_warn()  { log "WARN  $*" >&2; }
log_error() { log "ERROR $*" >&2; }

die() {
    log_error "$*"
    exit 1
}

# Mirror all further output into LOG_FILE. Once it exceeds LOG_MAX_BYTES, the newest half is kept.
# Skipped for --dry-run so that test runs never touch the real log.
log_setup_file() {
    [[ -n ${LOG_FILE:-} ]] || return 0
    (( DRY_RUN )) && return 0

    mkdir -p "$(dirname "$LOG_FILE")" || die "Cannot create log directory for $LOG_FILE"
    if [[ -f $LOG_FILE ]] && (( $(stat -c %s "$LOG_FILE") > LOG_MAX_BYTES )); then
        # tail -c may cut the first line in half, so drop it
        tail -c "$(( LOG_MAX_BYTES / 2 ))" "$LOG_FILE" | tail -n +2 > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
    exec > >(tee -a "$LOG_FILE") 2>&1
}
