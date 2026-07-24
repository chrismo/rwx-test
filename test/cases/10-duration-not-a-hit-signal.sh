#!/usr/bin/env bash
# Demonstrates that task duration says nothing about whether a task cached. A
# cache-hit task still reports a nonzero CompletedRuntimeSeconds, because that
# clock includes layer assembly. The only reliable hit/miss signal is
# Status.FinishedSubStatus.
#
# Two identical runs; on the second, `work` cache-hits and the case asserts its
# reported runtime is still > 0.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/rwx.sh"

CONFIG=".rwx/cache-10-duration-not-a-hit-signal.yml"

start_case "10 — duration is not a cache-hit signal"

rwx_run dur-1 "$CONFIG" >/dev/null
rwx_run dur-2 "$CONFIG" >/dev/null

assert_run_succeeded dur-1
assert_run_succeeded dur-2

# Second run reuses the first...
assert_cache_hit dur-2 work
# ...yet the clock still shows time spent. Duration can't distinguish the two.
assert_runtime_positive dur-2 work

finish
