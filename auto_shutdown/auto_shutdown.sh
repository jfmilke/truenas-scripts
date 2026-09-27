#!/usr/bin/env bash
#
# auto_shutdown.sh - power off TrueNAS when it has been idle.
#
# Meant to run every 5 minutes as root from a TrueNAS Cron Job. Each run:
#   1. runs every enabled check (lib/check_*.sh); busy or unknown = "active"
#   2. remembers when the NAS was last active
#   3. shuts down once it has been idle for IDLE_MINUTES
#
# Usage: auto_shutdown.sh [--dry-run] [-h|--help]
#   --dry-run  run all checks and print the decision, but change no state and never shut down

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly CONF_FILE="$SCRIPT_DIR/auto_shutdown.conf"
DRY_RUN=0
CHECKS_BUSY=0

# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=lib/http.sh
source "$SCRIPT_DIR/lib/http.sh"
# shellcheck source=lib/state.sh
source "$SCRIPT_DIR/lib/state.sh"
# shellcheck source=lib/notify.sh
source "$SCRIPT_DIR/lib/notify.sh"
# shellcheck source=lib/shutdown.sh
source "$SCRIPT_DIR/lib/shutdown.sh"
for check_file in "$SCRIPT_DIR"/lib/check_*.sh; do
    # shellcheck source=/dev/null
    source "$check_file"
done

usage() {
    sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

parse_args() {
    local arg
    for arg in "$@"; do
        case $arg in
            --dry-run)   DRY_RUN=1 ;;
            -h|--help)   usage; exit 0 ;;
            *)           usage >&2; die "Unknown argument: $arg" ;;
        esac
    done
}

# Only one run at a time (cron could start the next before a slow check is done).
acquire_lock() {
    exec 9< "${BASH_SOURCE[0]}"
    flock -n 9 || { log_info "Another run is in progress - exiting"; exit 0; }
}

# Run every enabled check, log its verdict, and set CHECKS_BUSY=1 if any is not idle.
run_checks() {
    local name output rc tag line

    for name in "${ENABLED_CHECKS[@]}"; do
        if ! declare -F "check_$name" > /dev/null; then
            log_warn "Unknown check '$name' in ENABLED_CHECKS - treating as busy"
            CHECKS_BUSY=1
            continue
        fi

        output=$("check_$name")
        rc=$?
        case $rc in
            0) tag="idle   " ;;
            1) tag="BUSY   " ;;
            *) tag="UNKNOWN" ;;
        esac
        (( rc == 0 )) || CHECKS_BUSY=1
        track_unknown_check "$name" "$rc" "${output//$'\n'/; }"

        while IFS= read -r line; do
            log_info "[$tag] $name: $line"
        done <<< "$output"
    done
}

# Refresh the idle timer and shut down once it has run out.
decide() {
    local now last_active boot idle_secs
    now=$(date +%s)

    if ! state_exists last_active; then
        # No history yet (first run ever, or state was cleared): don't judge idleness from
        # boot time - that would shut down immediately if the NAS was already up longer than
        # IDLE_MINUTES before this cron job started. Just record activity now; the next run
        # (5 minutes later) has a real baseline to judge from.
        state_set last_active "$now"
        log_info "Decision: no history yet - staying up"
        return 0
    fi

    last_active=$(state_get last_active)

    if (( CHECKS_BUSY )); then
        state_set last_active "$now"
        log_info "Decision: active - staying up"
        return 0
    fi

    # Booting counts as activity: after the nightly power-on the NAS gets a grace period.
    boot=$(boot_epoch)
    (( boot > last_active )) && last_active=$boot

    idle_secs=$(( now - last_active ))
    if (( idle_secs < IDLE_MINUTES * 60 )); then
        log_info "Decision: idle for $(( idle_secs / 60 )) of $IDLE_MINUTES min - staying up"
        return 0
    fi

    log_info "Decision: idle for $(( idle_secs / 60 )) min - shutting down"
    do_shutdown "$(( idle_secs / 60 ))"
}

main() {
    parse_args "$@"
    config_load
    http_init
    log_setup_file
    (( DRY_RUN )) || acquire_lock

    (( DRY_RUN )) && log_info "DRY-RUN: nothing is changed and the NAS is not shut down"
    run_checks
    decide
}

main "$@"
