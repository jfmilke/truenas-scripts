#!/usr/bin/env bash
# Check: is TrueNAS itself busy?
#   - any middleware job that is RUNNING or WAITING (replication, cloud sync, rsync,
#     SMART tests, snapshots, updates, ...), except
#       * the cron job that runs this very script (the middleware shows it as a running
#         "cronjob.run" job, so without this exception we would always be busy)
#       * methods listed in JOB_IGNORE_METHODS
#   - a ZFS scrub or resilver in progress (also catches ones started from the shell)
# API: midclt call core.get_jobs / cronjob.query <filters> <options>

# JSON list of the ids of the cron jobs whose command contains this script's file name.
own_cronjob_ids() {
    local ids
    ids=$(midclt call cronjob.query '[]' '{"select": ["id", "command"]}' 2> /dev/null \
        | jq -c --arg script "${0##*/}" '[.[] | select(.command | contains($script)) | .id]' 2> /dev/null)
    echo "${ids:-[]}"
}

check_truenas() {
    local jobs own_ids ignore_json findings kind text pools busy=0

    jobs=$(midclt call core.get_jobs \
        '[["state", "in", ["RUNNING", "WAITING"]]]' \
        '{"select": ["method", "arguments", "description", "state"]}' 2>&1) \
        || { echo "midclt core.get_jobs failed: $jobs"; return 2; }

    own_ids=$(own_cronjob_ids)
    ignore_json=$(printf '%s\n' "${JOB_IGNORE_METHODS[@]}" | jq -R . | jq -s .)

    # One "KIND<TAB>text" line per job: OWN (this script), IGNORED (JOB_IGNORE_METHODS) or BUSY.
    # shellcheck disable=SC2016  # jq variables, not shell ones
    findings=$(jq -r --argjson own "$own_ids" --argjson ignore "$ignore_json" '
        .[]
        | .method as $method
        | "\($method) [\(.state)] \(.description // "")" as $text
        | if $method == "cronjob.run" and ((.arguments[0] as $id | $own | index($id)) != null)
          then "OWN\t\($text)"
          elif ($ignore | index($method)) != null then "IGNORED\t\($text)"
          else "BUSY\t\($text)" end' <<< "$jobs") \
        || { echo "cannot parse core.get_jobs output"; return 2; }

    while IFS=$'\t' read -r kind text; do
        [[ -n $kind ]] || continue
        case $kind in
            BUSY)    echo "job running: $text"; busy=1 ;;
            OWN)     echo "job ignored (this script's own cron job): $text" ;;
            IGNORED) echo "job ignored (JOB_IGNORE_METHODS): $text" ;;
        esac
    done <<< "$findings"

    pools=$(zpool status 2>&1) || { echo "zpool status failed: $pools"; return 2; }
    if grep -Eq 'scan: +(scrub|resilver) in progress' <<< "$pools"; then
        echo "ZFS scrub or resilver in progress"
        busy=1
    fi

    (( busy )) || echo "no blocking jobs, no scrub/resilver"
    return "$busy"
}
