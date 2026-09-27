#!/usr/bin/env bash
# Check: is a known job about to start?
#
# Bridges the gaps between scheduled jobs, where every service is briefly idle
# although more work is coming. Entries in SCHEDULED_STARTS look like
# "03:00" or "04:00@1,2" (only on those days of the month). Windows must not
# cross midnight.

# in_csv VALUE "a,b,c" - is VALUE one of the comma-separated items?
in_csv() {
    [[ ",$2," == *",$1,"* ]]
}

check_schedule() {
    local now_min today entry time days start_min delta busy=0

    now_min=$(( 10#$(date +%H) * 60 + 10#$(date +%M) ))
    today=$(( 10#$(date +%d) ))

    for entry in "${SCHEDULED_STARTS[@]}"; do
        if [[ ! $entry =~ ^[0-9]{1,2}:[0-9]{2}(@[0-9]{1,2}(,[0-9]{1,2})*)?$ ]]; then
            echo "invalid SCHEDULED_STARTS entry '$entry' (expected HH:MM or HH:MM@day,day)"
            return 2
        fi

        time=${entry%%@*}
        days=""
        [[ $entry == *@* ]] && days=${entry#*@}
        if [[ -n $days ]] && ! in_csv "$today" "$days"; then
            continue
        fi

        start_min=$(( 10#${time%%:*} * 60 + 10#${time##*:} ))
        delta=$(( start_min - now_min ))
        if (( delta >= 0 && delta <= SCHEDULE_LOOKAHEAD_MINUTES )); then
            echo "scheduled start at $time is $delta min away"
            busy=1
        fi
    done

    (( busy )) || echo "no scheduled start within $SCHEDULE_LOOKAHEAD_MINUTES min"
    return "$busy"
}
