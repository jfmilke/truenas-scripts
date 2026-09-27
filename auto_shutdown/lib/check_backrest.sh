#!/usr/bin/env bash
# Check: is Backrest busy, or about to be?
# API: https://garethgeorge.github.io/backrest/docs/api  (POST /v1.Backrest/GetOperations)
#
# Backrest lists its upcoming scheduled runs as STATUS_PENDING operations with a start
# time, so its schedule needs no copy in SCHEDULED_STARTS. From one response this check finds:
#   busy  a running operation (STATUS_INPROGRESS)
#   busy  a pending operation whose start time has passed (due, waiting to start)
#   busy  a pending operation starting within SCHEDULE_LOOKAHEAD_MINUTES
#   idle  everything else (finished operations, runs further in the future)
#
# The response format is not a stable API. Anything unexpected - a missing "operations" list,
# a status name we do not know, a pending run without start time - is reported as unknown
# ("API changed?"): that blocks the shutdown, and track_unknown_check sends a notification.

# jq program (the $variables are jq's, not the shell's); prints one "KIND<TAB>text" line per relevant operation (KIND: RUNNING, DUE, SOON, PROBLEM).
# shellcheck disable=SC2016
readonly BACKREST_JQ='
    def minutes($ms): ($ms / 60000) | floor;

    (now * 1000) as $now
    | ["STATUS_SUCCESS", "STATUS_WARNING", "STATUS_ERROR",
       "STATUS_SYSTEM_CANCELLED", "STATUS_USER_CANCELLED"] as $final
    | (if type != "object" then error("response is not a JSON object")
       elif (has("operations") | not) then
           (if length == 0 then [] else error("response has no operations list, keys: \(keys | join(","))") end)
       elif (.operations | type) != "array" then error("operations is not a list")
       else .operations end)
    | .[]
    | (.planId // "?") as $plan
    | (.status // "STATUS_UNKNOWN") as $status
    | (try (.unixTimeStartMs | tonumber) catch null) as $start
    | if ($final | index($status)) then empty
      elif $status == "STATUS_INPROGRESS" then "RUNNING\t\($plan) is running"
      elif $status == "STATUS_PENDING" then
          if $start == null then "PROBLEM\tpending run of \($plan) has no start time"
          elif $start <= $now then "DUE\t\($plan) is due and waiting to start"
          elif ($start - $now) <= ($window * 60000) then "SOON\tnext run of \($plan) in \(minutes($start - $now)) min"
          else empty end
      else "PROBLEM\tunrecognised status \($status) on a run of \($plan)" end'

check_backrest() {
    require_config BACKREST_URL || return 2

    local auth=() body findings kind text rc=0
    [[ -n $BACKREST_USER ]] && auth=(--user "$BACKREST_USER:$BACKREST_PASSWORD")

    # The API rejects an empty request ("empty selector"); an empty selector object means "all plans".
    body=$(http_request "${auth[@]}" \
        --request POST --header 'Content-Type: application/json' \
        --data '{"selector": {}, "lastN": 200}' \
        "$BACKREST_URL/v1.Backrest/GetOperations") \
        || { http_failure_verdict $? "Backrest"; return; }

    findings=$(jq -r --argjson window "$SCHEDULE_LOOKAHEAD_MINUTES" "$BACKREST_JQ" <<< "$body" 2>&1) \
        || { echo "Backrest response has an unexpected format (API changed?): $findings"; return 2; }

    while IFS=$'\t' read -r kind text; do
        [[ -n $kind ]] || continue
        if [[ $kind == PROBLEM ]]; then
            echo "unexpected Backrest data (API changed?): $text"
            rc=2
        else
            echo "$text"
            (( rc == 2 )) || rc=1
        fi
    done <<< "$findings"

    (( rc != 0 )) || echo "nothing running or scheduled within $SCHEDULE_LOOKAHEAD_MINUTES min"
    return "$rc"
}
