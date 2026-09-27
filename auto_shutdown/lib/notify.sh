#!/usr/bin/env bash
# Notifications via ntfy (https://docs.ntfy.sh/publish/). Disabled while NTFY_URL is empty.
#   priority "low"     routine information (the NAS is shutting down)
#   priority "default" needs your attention
# A failed notification is only logged; it never changes what the script does.

# notify PRIORITY TITLE MESSAGE [TAGS]
notify() {
    local priority=$1 title=$2 message=$3 tags=${4:-}
    [[ -n $NTFY_URL ]] || return 0

    if (( DRY_RUN )); then
        log_info "DRY-RUN: would notify [$priority] $title: $message"
        return 0
    fi

    local headers=(--header "Title: $title" --header "Priority: $priority")
    [[ -n $tags ]] && headers+=(--header "Tags: $tags")
    [[ -n $NTFY_TOKEN ]] && headers+=(--header "Authorization: Bearer $NTFY_TOKEN")
    http_request "${headers[@]}" --data-raw "$message" "$NTFY_URL" > /dev/null \
        || log_warn "ntfy notification failed ($title): $(http_last_error)"
    return 0
}

# notify_once KEY COOLDOWN_SECONDS PRIORITY TITLE MESSAGE [TAGS]
# Like notify, but at most once per cooldown for the same KEY (cron runs every 5 minutes).
notify_once() {
    local key=$1 cooldown=$2 now last
    shift 2
    [[ -n $NTFY_URL ]] || return 0

    now=$(date +%s)
    last=$(state_get "notified_$key")
    (( now - last >= cooldown )) || return 0

    notify "$@"
    state_set "notified_$key" "$now"
}

# track_unknown_check CHECK RC REASON
# A check that keeps returning "unknown" (rejected API key, failing service) silently blocks
# every shutdown, so tell the owner - but only once it has lasted NTFY_UNKNOWN_MINUTES:
# services that are still starting up right after boot are normal.
track_unknown_check() {
    local name=$1 rc=$2 reason=$3 key="unknown_$1" now first

    if (( rc < 2 )); then
        state_unset "$key"
        return 0
    fi

    now=$(date +%s)
    first=$(state_get "$key")
    if (( first == 0 )); then
        first=$now
        state_set "$key" "$first"
    fi
    (( now - first >= NTFY_UNKNOWN_MINUTES * 60 )) || return 0

    notify_once "$key" $(( NTFY_REPEAT_HOURS * 3600 )) default \
        "$(hostname): check '$name' keeps failing" \
        "Unknown for $(( (now - first) / 60 )) min, so the NAS will not shut down. $reason" warning
}
