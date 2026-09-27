#!/usr/bin/env bash
# Persistent state, one small file per name in STATE_DIR (last_active, network counters,
# notification bookkeeping). All writes are skipped in --dry-run. Needs STATE_DIR and DRY_RUN.

# state_exists NAME - true if a value has ever been recorded for NAME.
state_exists() {
    [[ -e "$STATE_DIR/$1" ]]
}

# state_get NAME - the stored epoch/number, or 0 when there is none.
state_get() {
    local file="$STATE_DIR/$1" value=0
    [[ -r $file ]] && value=$(<"$file")
    [[ $value =~ ^[0-9]+$ ]] || value=0
    echo "$value"
}

# state_set NAME VALUE
state_set() {
    (( DRY_RUN )) && return 0
    mkdir -p "$STATE_DIR" && echo "$2" > "$STATE_DIR/$1"
}

state_unset() {
    (( DRY_RUN )) && return 0
    rm -f "$STATE_DIR/$1"
}

# Epoch seconds at which the system booted.
boot_epoch() {
    local uptime_secs
    uptime_secs=$(cut -d. -f1 /proc/uptime)
    echo $(( $(date +%s) - uptime_secs ))
}
