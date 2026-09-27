# TrueNAS Scripts

A variety of scripts which help administrating a TrueNAS system.

> [!NOTE]
> Each script performing dangerous operations is marked as such. Use at your own discretion.
>
> The structure will change depending on added scripts.  
> As of now, all script utility lie below `auto_shutdown` but may be sourced into a shared folder when the need emerges.

## Environment

The scripts are verified to run on TrueNAS 25.10.

I recommend to:

- Be able to wake your NAS remotely
- Don't expose the NAS to the internet (only by VPN)

Otherwise, the core essence of my preferred TrueNAS setup:

- Install [Dockhand](https://dockhand.pro/) via TrueNAS App Catalog
- Manage **all other Docker containers** using Dockhand
- Use a 24/7 running Raspberry Pi to
  - Access your LAN via VPN
  - Wake your NAS via WOL on demand
  - Wake your NAS via WOL during each night for nightly jobs

## Script: auto_shutdown.sh

Full reference: [auto_shutdown/README.md](auto_shutdown/README.md)

> [!CAUTION]
> This script will shutdown your NAS.

> [!NOTE]
> By default, all checks are enabled.  
> If you don't host immich or don't want to check network activity, remove the checks from `ENABLED_CHECKS`.

Shuts the NAS down if it has been idling for `IDLE_MINUTES`.  
Logs are written to `STATE_DIR` and trimmed automatically.

If any of the below busy conditions are `true` the system is busy.

| Check | Busy Condition |
| ----- | -------------- |
| `schedule` | a job from `SCHEDULED_STARTS` (see config) begins within the next 90 minutes |
| `backrest` | an operation is running or the next scheduled run starts within 90 minutes |
| `immich` | a queue has active, waiting or delayed jobs |
| `paperless` | there are active tasks |
| `truenas` | a middleware job is running/waiting, or a scrub/resilver is in progress |
| `sessions` | someone is logged in (SSH, console, shell) |
| `network` | the network interface moved more than `NET_MIN_BYTES_PER_SEC` (rx + tx) since the last run |

If configured, the script will send NTFY alerts when the shutdown was initiated or problems occurred in script execution.

### Setup

First, create your personal config file.

```bash
# Create your own config
cp auto_shutdown.conf.example auto_shutdown.conf

# Edit your config
nano auto_shutdown.conf

# Set restrictive permissions for your config (may hold API tokens)
chmod 600 auto_shutdown.conf

# Test it: prints every check and the decision, changes nothing, never shuts down
./auto_shutdown.sh --dry-run
```

Then, open TrueNAS GUI and create a cron job running each 5 minutes:  
_System → Advanced Settings → Cron Jobs → Add_

| Field | Value |
| ----- | ----- |
| Command | `/bin/bash /<path to scripts>/auto_shutdown.sh` |
| Run as | `root` |
| Schedule | `*/5 * * * *` |
