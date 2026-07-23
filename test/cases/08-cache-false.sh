#!/usr/bin/env bash
# Claim: `cache: false` is a per-task opt-out. The task re-executes on every
# run; its siblings keep caching normally.
#
# Both runs are identical — no salt, no edits — so everything cacheable should
# hit on the second pass. Anything that still executes is opted out.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/rwx.sh"

CONFIG=".rwx/cache-08-cache-false.yml"

start_case "08 — cache: false is a per-task opt-out"

rwx_run nocache-1 "$CONFIG" >/dev/null
rwx_run nocache-2 "$CONFIG" >/dev/null

assert_run_succeeded nocache-1
assert_run_succeeded nocache-2

# Opted out: re-executes despite identical inputs.
assert_executed nocache-2 never-cached

# Not opted out: identical inputs, so the second run reuses the first.
assert_cache_hit nocache-2 normally-cached

finish
