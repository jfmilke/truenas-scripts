# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

A collection of scripts for administering a personal TrueNAS 25.10 server. Currently contains
one script, `auto_shutdown/`, which powers the NAS off once it has been idle; `Docs/` holds
offline copies of the third-party API docs (Backrest, Immich, Paperless-ngx, TrueNAS) the
scripts are written against, plus design specs under `Docs/superpowers/specs/` — both are
gitignored (reference material, not project source).

Target runtime for every script here is the TrueNAS host itself: Debian, bash, root cron.
There is no dev/test environment on the NAS, so verification happens elsewhere (see below)
before anything is copied over.

## auto_shutdown

Shuts the NAS down after `IDLE_MINUTES` of inactivity, run every 5 minutes as a root Cron Job.
Full behavior and config reference: [auto_shutdown/README.md](auto_shutdown/README.md).

### Architecture

`auto_shutdown.sh` is a thin orchestrator: parse args, source every `lib/*.sh`, run checks,
decide. It has no logic of its own beyond that pipeline (see `auto_shutdown/auto_shutdown.sh`).

- **Checks** (`lib/check_*.sh`) are the extension point. Each file defines one `check_<name>`
  function that prints one reason per line to stdout and returns `0` (idle), `1` (busy), or `2`
  (unknown — treated as busy; used when a check can't tell, e.g. API error, timeout, missing
  config). To add a check: create `lib/check_<name>.sh` with a `check_<name>` function, add
  `<name>` to `ENABLED_CHECKS` in the conf. No registration elsewhere is needed — the main
  script sources every `lib/check_*.sh` glob automatically.
- **Utilities** (`lib/log.sh`, `config.sh`, `http.sh`, `state.sh`, `notify.sh`, `shutdown.sh`)
  are sourced once by the main script and used by checks: `http_request`/`http_failure_verdict`
  for API calls with consistent down/error handling, `state_get`/`state_set` for the one
  value-per-file state store, `notify`/`notify_once`/`track_unknown_check` for ntfy alerts,
  `require_config` for a check to bail out (rc 2) when its config vars are unset.
- **Decision loop**: every run refreshes `last_active` if any check is busy/unknown; boot time
  also counts as activity (grace period after the nightly power-on); shutdown fires once
  `now - last_active >= IDLE_MINUTES`. See `decide()` in `auto_shutdown.sh`.
- **State** lives in `STATE_DIR` (default `state/` next to the script), one small file per
  value (`last_active`, `net_rx`, `notified_<key>`, etc.) — not a single state blob. All state
  writes are no-ops under `--dry-run`.
- **Config** (`auto_shutdown.conf`, copied from `auto_shutdown.conf.example`) is sourced as
  bash and must be `chmod 600` (the script refuses to run otherwise). It holds API keys and
  tokens; `.gitignore` excludes every `*.conf` except `*.conf.example`, so new scripts should
  follow the same `<name>.conf` / `<name>.conf.example` pattern rather than inventing a new one.

### Key design points worth knowing before changing a check

- **Backrest's own schedule is used instead of a config copy**: `check_backrest.sh` reads
  Backrest's upcoming runs (`STATUS_PENDING` operations with a start time) to decide if the NAS
  should stay up, rather than requiring the schedule to be duplicated into
  `SCHEDULED_STARTS`. Any response shape it doesn't recognize is treated as unknown ("API
  changed?") rather than silently read as idle — this is deliberate fail-safe behavior, not a
  bug, since a parsing miss here could let the NAS shut down mid-backup.
- **`check_truenas.sh` excludes its own cron job**: the middleware reports the cron job that
  runs this very script as a running `cronjob.run` job. The check looks up cron job ids via
  `cronjob.query` matching on `auto_shutdown.sh` in the command, and only ignores `cronjob.run`
  entries for those ids — other cron jobs still count as busy.
- **`check_network.sh` measures interface byte-counter deltas** (rx+tx rate since last run),
  not connection tracking — a simpler design that trades away LAN-vs-internet and per-client
  detail for far less code and no kernel tunable dependency. Don't reintroduce conntrack-based
  filtering without discussing the tradeoff first.
- **A container/service that isn't running counts as idle** (connection refused), while any
  other failure (timeout, auth error, unparseable response) counts as unknown/busy — never
  silently idle.

### Verification workflow (no CI, no test suite in the repo)

There's no local runner for this script (it depends on `midclt`, `zpool`, real
Docker-hosted services, and `/sys/class/net`, none of which exist off the NAS). The workflow
used throughout this project's history, and the one to keep using:

1. `shellcheck -x -s bash auto_shutdown.sh lib/*.sh` and `bash -n` on every file — must stay
   clean.
2. Exercise real checks against the real services (Backrest/Immich/Paperless are reachable
   from this dev machine) from inside a `debian:12-slim` Docker container, which matches the
   NAS's bash/mawk/jq versions closely enough to catch portability bugs (e.g. `mawk` printing
   large numbers in scientific notation broke arithmetic; bash 3.2 on macOS doesn't reproduce
   `set -u` issues with empty arrays that bash 5.2 does). Stub only what can't be reached from
   here: `midclt`, `zpool`, `/sys/class/net`, `/proc/net/route`, `who`.
3. `./auto_shutdown.sh --dry-run` is the intended test entry point on the real NAS too — it
   runs every check and prints the decision without writing state or shutting down.
4. Full end-to-end (`--dry-run` on the NAS itself, `midclt` argument shapes, boot-time
   `nf_conntrack`-style OS specifics, an actual `system.shutdown` call) can only be confirmed
   by the user running it on the real hardware — say so explicitly rather than assuming
   something works because it passed in the container.

## Git

This repo has stricter-than-default rules for agents:

- Never run `git commit` or `git push` unprompted.
- Before any writing git action (commit, push, branch creation, etc.), ask for permission and
  explain what will be done and why. One approval does not cover a later action.
- If continuing a task requires a commit (e.g. a tool needs a clean tree), ask for permission to
  commit rather than doing it silently.
- Don't write unit tests for the shell scripts here — see the verification workflow above.
- Unless explicitly asked to fix it, only check `ReadMe.md` for problems and suggest fixes in
  chat; don't edit it directly.

## Docs/

Offline reference copies (HTML/markdown) of the Backrest, Immich, Paperless-ngx, and TrueNAS
25.10 middleware (`midclt`/`core.get_jobs`-style) APIs. Consult these before assuming an API
method's shape — several past bugs came from an assumption (Backrest's status enum, request
body shape) that these docs — or a live probe against the real service — would have caught
sooner. `Docs/superpowers/specs/` holds the dated design spec(s) for scripts in this repo;
keep them in sync when a script's behavior changes materially.
