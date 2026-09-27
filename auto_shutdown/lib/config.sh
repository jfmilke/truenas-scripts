#!/usr/bin/env bash
# Configuration: defaults, loading auto_shutdown.conf, validation helpers.
# Needs SCRIPT_DIR and CONF_FILE (set by auto_shutdown.sh).

# The settings below are read by the other scripts, which shellcheck does not see here.
# shellcheck disable=SC2034
config_set_defaults() {
    IDLE_MINUTES=15
    HTTP_TIMEOUT=10
    ENABLED_CHECKS=(schedule backrest immich paperless truenas sessions network)

    # schedule check
    SCHEDULED_STARTS=()
    SCHEDULE_LOOKAHEAD_MINUTES=90

    # service checks (no defaults: the app ports depend on your TrueNAS setup)
    BACKREST_URL="" BACKREST_USER="" BACKREST_PASSWORD=""
    IMMICH_URL=""   IMMICH_API_KEY=""
    PAPERLESS_URL="" PAPERLESS_TOKEN=""

    # truenas check
    JOB_IGNORE_METHODS=()

    # network check
    NET_INTERFACE=""              # empty: the interface holding the default route
    NET_MIN_BYTES_PER_SEC=3000

    # notifications (ntfy); disabled while NTFY_URL is empty
    NTFY_URL="" NTFY_TOKEN=""
    NTFY_UNKNOWN_MINUTES=30
    NTFY_REPEAT_HOURS=6

    # state and logging
    STATE_DIR="$SCRIPT_DIR/state"
    # LOG_FILE defaults to "$STATE_DIR/auto_shutdown.log" (see config_load); LOG_FILE="" disables it.
    LOG_MAX_BYTES=2097152    # a run logs about 1 KB: this keeps roughly 4-8 days of history
}

config_load() {
    config_set_defaults

    [[ -f $CONF_FILE ]] || die "Config file not found: $CONF_FILE (copy auto_shutdown.conf.example)"
    local mode
    mode=$(stat -c %a "$CONF_FILE")
    (( (8#$mode & 8#077) == 0 )) || die "$CONF_FILE holds secrets and must not be accessible by group/other (chmod 600)"

    # shellcheck source=/dev/null
    source "$CONF_FILE"

    : "${LOG_FILE=$STATE_DIR/auto_shutdown.log}"    # only when the conf left it unset
    config_require_tools
}

config_require_tools() {
    local tool
    for tool in curl jq midclt awk flock who hostname; do
        command -v "$tool" > /dev/null || die "Required tool not found: $tool"
    done
}

# For use inside checks: require_config VAR... || return 2
# Prints the reason and fails when one of the named variables is empty.
require_config() {
    local var missing=()
    for var in "$@"; do
        [[ -n ${!var:-} ]] || missing+=("$var")
    done
    (( ${#missing[@]} == 0 )) && return 0
    echo "missing in config: ${missing[*]}"
    return 1
}
