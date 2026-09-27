# TrueNAS Scripts

A variety of scripts which help administrating my TrueNAS.

Some notes about the TrueNAS setup these scripts are running on:

- TrueNAS is running on the UGREEN DXP2800
- Only Dockhand runs as a native TrueNAS app
- All other apps (Immich, Paperless, ...) are running as docker containers managed by Dockhand
- The NAS is only accessible from LAN or VPN
- Homeassistant running on a Raspberry Pi manages the VPN and can wake the NAS via WOL

## auto_shutdown

This script checks if the NAS is idling for a certain time and shuts it down if so.
It is meant to be used in tandem with WakeOnLAN or a timed BIOS boot to start it in the night for scheduled tasks (backups, immich jobs, database exports, ...).

1. Create your own `auto_shutdown.conf` based on the example and fill values
2. Call `auto_shutdown.sh` via Cronjob (i.e. each 5 minutes: `*/5 * * * *`) as root

The script currently checks:

- Scheduled jobs in the next 90 minutes noted in the `auto_shutdown.conf`
- Backrest via REST API if a backup is running or is scheduled within the next 90 minutes
- Immich via REST API if any jobs are currently running or queued
- Paperless via REST API if any tasks are currently running
- TrueNAS via `midclt` & `zpool status` if any jobs are running
- Active sessions via `who`
- Network activity via kernel byte counters if it exceeds a certain threshold

The script provides the following additional features:

- Use NTFY to inform about shutdowns (low prio) and problems (default prio)
- Log activity to `state/auto_shutdown.log` and auto-trim the file
