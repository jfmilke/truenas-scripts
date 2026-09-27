#!/usr/bin/env bash
# Check: is someone logged in (SSH, console, shell)?

check_sessions() {
    local sessions
    sessions=$(who)

    if [[ -n $sessions ]]; then
        echo "logged in: $(awk '{printf "%s@%s ", $1, $2}' <<< "$sessions")"
        return 1
    fi
    echo "nobody logged in"
}
