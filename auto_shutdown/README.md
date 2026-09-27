# auto_shutdown

Powers a TrueNAS 25.10 server off once it has been idle for `IDLE_MINUTES` (default 15).

Idle means all of these are true:

| Check | Busy when |
|---|---|
| `schedule` | a job from `SCHEDULED_STARTS` (e.g. Immich's night tasks) begins within the next 90 minutes |
| `backrest` | an operation is running or due, or the next scheduled run (read from Backrest itself) starts within 90 minutes |
| `immich` | a queue has active, waiting or delayed jobs |
| `paperless` | there are active tasks |
| `truenas` | a middleware job is running/waiting, or a scrub/resilver is in progress |
| `sessions` | someone is logged in (SSH, console, shell) |
| `network` | the network interface moved more than `NET_MIN_BYTES_PER_SEC` (rx + tx) since the last run |

Anything a check cannot determine (API error, timeout, missing config) counts as busy.
A container that is not running counts as idle.

## Install

1. Copy the `auto_shutdown` folder to a pool dataset, e.g. `/mnt/tank/scripts/auto_shutdown/`.
2. `cp auto_shutdown.conf.example auto_shutdown.conf && chmod 600 auto_shutdown.conf`, then fill in
   the URLs, the Immich API key, the Paperless token and your `SCHEDULED_STARTS`.
3. Try it: `./auto_shutdown.sh --dry-run` (see below).
4. *System > Advanced > Cron Jobs > Add*: command `/mnt/tank/scripts/auto_shutdown/auto_shutdown.sh`,
   user `root`, every 5 minutes (`*/5 * * * *`), hide standard output (it is logged to
   `state/auto_shutdown.log` anyway).

## Notifications (ntfy)

Set `NTFY_URL` (including the topic; optionally `NTFY_TOKEN`) in the config. Empty = off.

| Event | Priority |
|---|---|
| The NAS is shutting down (sent just before the shutdown) | low |
| `system.shutdown` failed | default |
| A check has been "unknown" for `NTFY_UNKNOWN_MINUTES` (default 30) - it silently blocks every shutdown, e.g. after an API key was revoked. Repeated at most every `NTFY_REPEAT_HOURS` (default 6). | default |

A failing notification is only logged as a warning. `--dry-run` sends nothing and logs what it would send.

## Dry run

```
./auto_shutdown.sh --dry-run
```

Runs every check and prints one line per finding plus the decision. It writes no state and
never shuts down. Things to look at on the first runs:

- **truenas**: every running job is listed with its method. The cron job that runs this script
  shows up as a running `cronjob.run` job; it is recognised by its command (it must contain
  `auto_shutdown.sh`) and reported as "this script's own cron job". Any other job that is always
  running goes into `JOB_IGNORE_METHODS`.
- **network**: the first run only records the counters; later runs log the measured rate of the
  interface (`eth0 moved 0.4 KB/s ... (limit 3.0 KB/s)`). Let it run for a few days, look at the
  idle values in `state/auto_shutdown.log` and set `NET_MIN_BYTES_PER_SEC` clearly above them,
  but low enough to notice light browsing (one photo page is roughly 1-3 MB).
- **backrest**: Backrest lists its upcoming scheduled runs as `STATUS_PENDING` operations with a
  start time; the check uses them, so Backrest's schedule needs no copy in `SCHEDULED_STARTS`.
  Its response format is not a stable API. If it changes (unknown status, missing field) the
  check reports "unknown (API changed?)", the NAS stays up, and ntfy tells you after
  `NTFY_UNKNOWN_MINUTES`.
- **sessions**: your own SSH session counts as logged in, so a dry-run over SSH is always busy
  here.

## Files

```
auto_shutdown.sh            main script: arguments, run checks, decide
auto_shutdown.conf.example  configuration template
lib/log.sh config.sh http.sh state.sh notify.sh shutdown.sh    utilities
lib/check_*.sh              one check per file: check_<name> prints reasons, returns 0 idle / 1 busy / 2 unknown
```

Adding a check: create `lib/check_<name>.sh` with a `check_<name>` function and add the name to
`ENABLED_CHECKS`.

## Notes

- Waking the NAS up (BIOS/RTC power-on, Wake-on-LAN) is not part of this script. After every
  boot the idle timer starts from the boot time, so the NAS always stays up for at least
  `IDLE_MINUTES`.
- If you change the Immich schedule, update `SCHEDULED_STARTS`. Backrest's schedule is picked up automatically.
