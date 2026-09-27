# auto_shutdown

Shuts a TrueNAS 25.10 server down once it has been idle for `IDLE_MINUTES` (default `15`
minutes), so it only needs to be powered on for as long as something actually needs it.

Best to use with Wake-on-LAN or a timed BIOS/RTC power-on.

> [!CAUTION]
> This script shuts the NAS down. Read [Testing](#testing) and try `--dry-run` before you
> rely on it.

## What it checks

The NAS counts as idle only when **every** enabled check says so. Anything a check can't
determine (API error, timeout, missing config) counts as busy, and a service that isn't
running counts as idle — nothing here can mistake a stopped container for "busy work".

| Check | Busy Condition |
| ----- | -------------- |
| `schedule` | a job from `SCHEDULED_STARTS` begins within `SCHEDULE_LOOKAHEAD_MINUTES` |
| `backrest` | an operation is running or due, or Backrest's own next scheduled run starts within `SCHEDULE_LOOKAHEAD_MINUTES` |
| `immich` | a queue has active, waiting or delayed jobs |
| `paperless` | there are active tasks |
| `truenas` | a middleware job is running/waiting, or a scrub/resilver is in progress |
| `sessions` | someone is logged in (SSH, console, shell) |
| `network` | the network interface moved more than `NET_MIN_BYTES_PER_SEC` (rx + tx) since the last run |

> [!NOTE]
> All checks are enabled by default. Remove a name from `ENABLED_CHECKS` in the config to
> turn one off entirely (e.g. you don't run Immich, or don't want the network check).

## Install

```bash
# 1. Copy this folder to a pool dataset to survive TrueNAS Updates.
#    E.g.: /mnt/tank/scripts/auto_shutdown

# 2. Create your own config from the template
cp auto_shutdown.conf.example auto_shutdown.conf

# 3. Customize & fill in the service URLs/keys (see Configuration below).
#    Then restict access.
nano auto_shutdown.conf
chmod 600 auto_shutdown.conf

# 4. Test if it works.
#    '--dry-run' prints each check but writes nothing & doesn't execute shutdown.
./auto_shutdown.sh --dry-run
```

Then, open the TrueNAS GUI and add a cron job:  
_System → Advanced Settings → Cron Jobs → Add_

| Field | Value |
| ----- | ----- |
| Command | `/bin/bash /mnt/tank/scripts/auto_shutdown/auto_shutdown.sh` |
| Run as | `root` |
| Schedule | every 5 minutes (`*/5 * * * *`) |

## Configuration

All settings live in `auto_shutdown.conf`. `auto_shutdown.conf.example` is just a template to start from.
Only the service URLs/keys below need filling in — everything else has a working default.

### General

| Variable | Default | Purpose |
| -------- | ------- | ------- |
| `IDLE_MINUTES` | `15` | minutes without activity before shutdown |
| `ENABLED_CHECKS` | all seven checks | which checks run; remove one to disable it |
| `HTTP_TIMEOUT` | `10` | seconds before an API request counts as failed |

### Schedule

| Variable | Default | Purpose |
| -------- | ------- | ------- |
| `SCHEDULED_STARTS` | `("02:00")` | start times of jobs the script can't otherwise see (e.g. Immich's night tasks). Format `HH:MM` or `HH:MM@day,day` (only on those days of the month). Backrest tasks don't need to be listed here, they are read from the service API. |
| `SCHEDULE_LOOKAHEAD_MINUTES` | `90` | how far ahead the `schedule` and `backrest` checks look. If a future task lies beyond that, the system isn't kept awake. |

### Services

| Variable | Default | Purpose |
| -------- | ------- | ------- |
| `BACKREST_URL` | `http://localhost:9898` | Backrest's API |
| `BACKREST_USER` / `BACKREST_PASSWORD` | empty | basic auth; leave empty if Backrest auth is off |
| `IMMICH_URL` | `http://localhost:2283` | Immich's API |
| `IMMICH_API_KEY` | empty — **required** | needs permission to read `/api/queues` |
| `PAPERLESS_URL` | `http://localhost:8000` | Paperless-ngx's API |
| `PAPERLESS_TOKEN` | empty — **required** | from "My Profile" in the Paperless web UI |

### TrueNAS

| Variable | Default | Purpose |
| -------- | ------- | ------- |
| `JOB_IGNORE_METHODS` | empty | middleware job methods to ignore if one runs continuously (`--dry-run` prints every running job's method) |

### Network

| Variable | Default | Purpose |
| -------- | ------- | ------- |
| `NET_MIN_BYTES_PER_SEC` | `3000` | rx+tx rate (bytes/s) above which the interface counts as busy |
| `NET_INTERFACE` | empty | interface to watch; empty = the one holding the default route |

### Notifications (ntfy)

| Variable | Default | Purpose |
| -------- | ------- | ------- |
| `NTFY_URL` | empty = off | topic URL to publish to |
| `NTFY_TOKEN` | empty | bearer token, if the topic needs auth |
| `NTFY_UNKNOWN_MINUTES` | `30` | how long a check must stay "unknown" before you're told |
| `NTFY_REPEAT_HOURS` | `6` | minimum gap between repeat notifications for the same problem |

### State & logging

| Variable | Default | Purpose |
| -------- | ------- | ------- |
| `STATE_DIR` | `state/` next to the script | where the idle timer, network counters and log live |
| `LOG_FILE` | `$STATE_DIR/auto_shutdown.log` | set to `""` to disable logging |
| `LOG_MAX_BYTES` | `2097152` (2 MB) | log is trimmed to its newest half once it passes this size |

## Notifications

If `NTFY_URL` is set, the script publishes:

| Event | Priority |
| ----- | -------- |
| The NAS is shutting down (sent just before the shutdown) | low |
| `system.shutdown` failed | default |
| A check has been "unknown" for `NTFY_UNKNOWN_MINUTES` — this silently blocks every shutdown, e.g. after an API key is revoked. Repeated at most every `NTFY_REPEAT_HOURS`. | default |

A failed notification is only logged as a warning; it never blocks a shutdown. `--dry-run`
sends nothing and logs what it would have sent.

## Testing

```bash
./auto_shutdown.sh --dry-run
```

Runs every check and prints the decision. Writes no state and never shuts down — safe to run
anytime, including repeatedly while tuning the config.

> [!NOTE]
> The very first real run has no history yet, so it always stays up and just records that moment as the baseline.

What to look at during those first runs:

- **`truenas`**: every running job is listed with its method, except this script's own cron
  job, which is recognized and silently ignored (not logged). Any other job that's always
  running belongs in `JOB_IGNORE_METHODS`.
- **`network`**: the first run only records a baseline; later runs log the measured rate
  (`eth0 moved 0.4 KB/s ... (limit 3.0 KB/s)`).

> [!TIP]
> Let the network check log for a few days, then read the idle values in
> `state/auto_shutdown.log` and set `NET_MIN_BYTES_PER_SEC` clearly above your idle noise
> floor — but low enough to still notice light browsing (one photo page is roughly 1-3 MB).

- **`backrest`**: Backrest's response format isn't a stable API. If it changes in a way the
  check doesn't recognize, it reports "unknown (API changed?)" rather than guessing — the NAS
  stays up, and ntfy tells you after `NTFY_UNKNOWN_MINUTES`.
- **`sessions`**: your own SSH session counts as logged in, so a dry-run over SSH always shows
  busy here.

## Extending

```
auto_shutdown.sh            main script: parse args, source lib/, run checks, decide
auto_shutdown.conf.example  configuration template
lib/log.sh config.sh http.sh state.sh notify.sh shutdown.sh    shared utilities
lib/check_*.sh              one check per file
```

Each check is a `check_<name>` function in `lib/check_<name>.sh` that prints one reason per
line and returns `0` (idle), `1` (busy) or `2` (unknown, treated as busy). To add one, drop a
new `lib/check_<name>.sh` next to the others and add `<name>` to `ENABLED_CHECKS` — no other
registration needed, the main script sources every `lib/check_*.sh` automatically.

## Good to know

- Waking the NAS up (BIOS/RTC power-on, Wake-on-LAN) isn't part of this script — after every
  boot the idle timer starts fresh from the boot time, so the NAS always stays up for at
  least `IDLE_MINUTES`.