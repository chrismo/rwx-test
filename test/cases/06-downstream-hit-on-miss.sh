#!/usr/bin/env bash
# Claim: a downstream task cache-hits even when its upstream was a cache MISS,
# provided the upstream produced identical output content.
#
# This is the single most useful thing to understand about RWX caching. Under
# key-prefix caching (the model most CI systems use), touching a build script
# invalidates everything downstream. Here it does not.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/rwx.sh"

CONFIG=".rwx/cache-06-downstream-hit-on-miss.yml"

start_case "06 — downstream cache hit despite upstream miss"

# Novel on every invocation — a fixed salt means RWX has already seen these
# inputs on a re-run and `write-foo` cache-hits, failing assert_executed for a
# reason that has nothing to do with the claim.
NONCE="$(date +%s)-$RANDOM"

rwx_run noise-a "$CONFIG" --init "noise=$NONCE-a" >/dev/null
rwx_run noise-b "$CONFIG" --init "noise=$NONCE-b" >/dev/null

assert_run_succeeded noise-a
assert_run_succeeded noise-b

# The upstream's own script inputs changed, so it must re-execute.
assert_diff_key noise-a noise-b write-foo
assert_executed noise-b write-foo

# But foo.txt is byte-identical both times, so the downstream key is unchanged
# and the result is reused outright.
assert_same_key noise-a noise-b hash-foo
assert_cache_hit noise-b hash-foo

finish
