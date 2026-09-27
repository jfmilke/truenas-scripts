#!/usr/bin/env bash
# Check: does Immich have jobs in its queues?
# API: GET /api/queues (header x-api-key) -> [{name, isPaused, statistics:{active,waiting,delayed,...}}]
# Paused queues are ignored for waiting/delayed jobs, since those will not run.

check_immich() {
    require_config IMMICH_URL IMMICH_API_KEY || return 2

    local body summary
    body=$(http_request --header "x-api-key: $IMMICH_API_KEY" "$IMMICH_URL/api/queues") \
        || { http_failure_verdict $? "Immich"; return; }

    summary=$(jq -r '
        [ .[]
          | select(.statistics.active > 0
                   or ((.isPaused | not) and (.statistics.waiting + .statistics.delayed) > 0))
          | "\(.name) (active \(.statistics.active), waiting \(.statistics.waiting), delayed \(.statistics.delayed))" ]
        | join(", ")' <<< "$body") \
        || { echo "Immich returned an unexpected response"; return 2; }

    if [[ -n $summary ]]; then
        echo "queues with work: $summary"
        return 1
    fi
    echo "no queue has jobs to run"
}
