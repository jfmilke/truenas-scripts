#!/usr/bin/env bash
# Check: is there traffic on the NAS's network interface?
#
# Compares the kernel's byte counters (rx + tx) of the interface with the values stored by the
# previous run and turns the difference into a rate. An open browser tab or idle SMB session
# moves almost nothing and does not count; traffic between containers stays on docker's
# internal bridge and never reaches the interface. Every run logs the measured rate, so the
# log shows your idle noise floor for choosing NET_MIN_BYTES_PER_SEC.

readonly NET_SYS_DIR=/sys/class/net

# The interface holding the default route, unless NET_INTERFACE says otherwise.
network_interface() {
    if [[ -n $NET_INTERFACE ]]; then
        echo "$NET_INTERFACE"
    else
        awk '$2 == "00000000" {print $1; exit}' /proc/net/route
    fi
}

# kbps BYTES_PER_SEC - e.g. 3400 -> "3.4 KB/s"
kbps() {
    echo "$(( $1 / 1000 )).$(( $1 % 1000 / 100 )) KB/s"
}

check_network() {
    local iface now rx tx prev_time prev_rx prev_tx rate

    iface=$(network_interface)
    if [[ ! -r $NET_SYS_DIR/$iface/statistics/rx_bytes ]]; then
        echo "no byte counters for network interface '${iface:-?}' (set NET_INTERFACE)"
        return 2
    fi

    now=$(date +%s)
    rx=$(<"$NET_SYS_DIR/$iface/statistics/rx_bytes")
    tx=$(<"$NET_SYS_DIR/$iface/statistics/tx_bytes")
    prev_time=$(state_get net_time)
    prev_rx=$(state_get net_rx)
    prev_tx=$(state_get net_tx)
    state_set net_time "$now"
    state_set net_rx "$rx"
    state_set net_tx "$tx"

    # No stored values yet, or the counters restarted from zero (reboot).
    if (( prev_time == 0 || now <= prev_time || rx < prev_rx || tx < prev_tx )); then
        echo "$iface: no baseline yet (first run or reboot), counters recorded"
        return 0
    fi

    rate=$(( (rx - prev_rx + tx - prev_tx) / (now - prev_time) ))
    echo "$iface moved $(kbps "$rate") over the last $(( now - prev_time )) s (limit $(kbps "$NET_MIN_BYTES_PER_SEC"))"
    (( rate <= NET_MIN_BYTES_PER_SEC ))
}
