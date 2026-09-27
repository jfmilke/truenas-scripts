#!/usr/bin/env bash
# HTTP helpers for the service checks.
#
#   body=$(http_request [curl args...] URL) || { http_failure_verdict $? "Label"; return; }
#
# http_request prints the response body on success. Failures are told apart:
#   HTTP_DOWN  - connection refused: the container is not running (= nothing to wait for)
#   HTTP_ERROR - anything else (timeout, 401, 500, ...): we cannot tell what is going on
# The detail of the last failure is kept in HTTP_ERROR_FILE, because http_request usually
# runs inside $(...) where it cannot set variables for its caller.

readonly HTTP_DOWN=10
readonly HTTP_ERROR=11

http_init() {
    HTTP_ERROR_FILE=$(mktemp)
    trap 'rm -f "$HTTP_ERROR_FILE"' EXIT
}

http_last_error() {
    cat "$HTTP_ERROR_FILE"
}

http_request() {
    local response rc code
    response=$(curl --silent --max-time "$HTTP_TIMEOUT" --write-out '\n%{http_code}' "$@")
    rc=$?

    if (( rc == 7 )); then
        echo "connection refused by ${*: -1}" > "$HTTP_ERROR_FILE"
        return "$HTTP_DOWN"
    elif (( rc != 0 )); then
        echo "curl failed (exit $rc) for ${*: -1}" > "$HTTP_ERROR_FILE"
        return "$HTTP_ERROR"
    fi

    code=${response##*$'\n'}
    local body=${response%$'\n'*}
    if [[ $code != 2* ]]; then
        body=${body//$'\n'/ }
        echo "HTTP $code from ${*: -1}: ${body:0:200}" > "$HTTP_ERROR_FILE"
        return "$HTTP_ERROR"
    fi
    printf '%s' "$body"
}

# Turn a failed http_request into a check result: prints the reason and
# returns 0 (idle: service not running) or 2 (unknown).
http_failure_verdict() {
    local rc=$1 label=$2
    if (( rc == HTTP_DOWN )); then
        echo "$label is not reachable - treating it as not running"
        return 0
    fi
    echo "$label query failed: $(http_last_error)"
    return 2
}
