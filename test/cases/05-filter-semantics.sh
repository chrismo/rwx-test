#!/usr/bin/env bash
# Covers plan items 04 (an include filter strips files off disk) and 05
# (negation semantics) — they are the same mechanism seen from two sides, so
# one config pins down both.
#
# Every task in this config asserts its own expectations with `test`, so a
# successful run IS the pass. The harness only has to confirm that each task
# actually executed rather than silently cache-hitting a stale result.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/rwx.sh"

CONFIG=".rwx/cache-05-filter-semantics.yml"

start_case "05 — filter semantics (allowlist trap, negation, ordering)"

run_id="$(rwx_run filters "$CONFIG")"

assert_run_succeeded filters

for task in \
  all-negated-is-a-denylist \
  one-positive-makes-it-an-allowlist \
  last-match-wins-include \
  last-match-wins-exclude \
  bare-entry-is-an-exact-path
do
  assert_task_succeeded filters "$task"
done

# The load-bearing one: prove the allowlist actually removed a file from disk,
# not just from the cache key.
assert_log_contains "$run_id" one-positive-makes-it-an-allowlist \
  "confirmed: unlisted files were stripped once a positive entry existed"

finish
