#!/usr/bin/env bash
# Claim: sibling tasks are independent cache units. Changing one task's inputs
# does not disturb another's cache key, and no filter is required to get that.
#
# This is the baseline every other caching test is measured against. If this
# fails, nothing else in the suite means what it says.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/rwx.sh"

CONFIG=".rwx/cache-01-native-task-isolation.yml"

# The salts must be novel on every invocation. A fixed `v1`/`v2` makes this
# test pass exactly once: the second time you run it, RWX has already seen
# those inputs and correctly serves `alpha` from cache, so `assert_executed`
# fails even though nothing is wrong. Cache-aware tests have to assume the
# cache remembers them.
NONCE="$(date +%s)-$RANDOM"

start_case "01 — native task isolation (no filters)"

rwx_run salt-v1 "$CONFIG" --init "alpha-salt=$NONCE-a" >/dev/null
rwx_run salt-v2 "$CONFIG" --init "alpha-salt=$NONCE-b" >/dev/null

assert_run_succeeded salt-v1
assert_run_succeeded salt-v2

# alpha consumes the salt, so its inputs genuinely changed.
assert_diff_key salt-v1 salt-v2 alpha
assert_executed salt-v2 alpha

# beta does not. Its key must be untouched — and because run 1 already
# populated it, run 2 must reuse that result outright.
assert_same_key salt-v1 salt-v2 beta
assert_cache_hit salt-v2 beta

finish
