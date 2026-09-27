#!/usr/bin/env bash
# Check: does Paperless-ngx have active tasks (consumption, indexing, ...)?
# API: GET /api/tasks/active/ - exists from API version 10 on, hence the version in the Accept header.
# The response shape is not spelled out in the docs: a plain list or {"results": [...]} is
# understood, anything else is reported as unknown (which blocks the shutdown).

check_paperless() {
    require_config PAPERLESS_URL PAPERLESS_TOKEN || return 2

    local body summary
    body=$(http_request \
        --header "Authorization: Token $PAPERLESS_TOKEN" \
        --header 'Accept: application/json; version=10' \
        "$PAPERLESS_URL/api/tasks/active/") \
        || { http_failure_verdict $? "Paperless"; return; }

    summary=$(jq -r '
        (if type == "array" then . elif has("results") then .results else error("unexpected shape") end)
        | map("\(.task_type // .task_name // "task") (\(.status // "active"))")
        | join(", ")' <<< "$body") \
        || { echo "Paperless returned an unexpected response"; return 2; }

    if [[ -n $summary ]]; then
        echo "active tasks: $summary"
        return 1
    fi
    echo "no active tasks"
}
