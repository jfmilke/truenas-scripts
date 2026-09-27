#!/usr/bin/env bash
# The one place that actually powers the machine off.

# do_shutdown IDLE_MINUTES
do_shutdown() {
    local minutes=$1 reason="auto_shutdown: idle for $1 minutes"

    # Notify first: the network goes down together with the NAS.
    notify low "$(hostname): shutting down" "Idle for $minutes minutes." zzz

    if (( DRY_RUN )); then
        log_info "DRY-RUN: would run: midclt call system.shutdown \"$reason\""
        return 0
    fi

    log_info "Running: midclt call system.shutdown \"$reason\""
    if ! midclt call system.shutdown "\"$reason\""; then
        log_error "system.shutdown failed"
        notify default "$(hostname): shutdown failed" "midclt system.shutdown returned an error; the NAS is still on." warning
    fi
}
