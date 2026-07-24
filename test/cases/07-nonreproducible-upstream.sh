#!/usr/bin/env bash
# Tests the claim "an unfiltered upstream with non-reproducible output defeats
# every downstream filter."
#
# Verdict encoded below: the strong form is false. Non-reproducible output
# poisons a downstream task only when the varying bytes are inside that task's
# filter. Two independent defenses work — filter the consumer, or prune the
# producer's output layer — and the second is better because it applies once.
#
# Both runs are identical. Any key that moves, moves because of upstream
# non-determinism alone.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/rwx.sh"

CONFIG=".rwx/cache-07-nonreproducible-upstream.yml"

start_case "07 — non-reproducible upstream vs downstream filters"

rwx_run noisy-1 "$CONFIG" >/dev/null
rwx_run noisy-2 "$CONFIG" >/dev/null

assert_run_succeeded noisy-1
assert_run_succeeded noisy-2

printf '\n  cache keys across two identical runs:\n'
for t in downstream-unfiltered downstream-filtered downstream-of-pruned; do
  a="$(cache_key noisy-1 "$t")"; b="$(cache_key noisy-2 "$t")"
  if [[ "$a" == "$b" ]]; then verdict="HELD "; else verdict="MOVED"; fi
  printf '    %-22s %s\n' "$t" "$verdict"
done
printf '\n'

# The claim's true core: an unfiltered consumer of volatile output is poisoned.
assert_diff_key noisy-1 noisy-2 downstream-unfiltered
assert_executed noisy-2 downstream-unfiltered

# ...but a consumer whose filter excludes the volatile bytes is immune, which
# is where the strong form of the claim fails.
assert_same_key noisy-1 noisy-2 downstream-filtered
assert_cache_hit noisy-2 downstream-filtered

# ...and pruning the producer's output layer immunizes consumers that carry no
# filter at all. One fix at the source instead of one per consumer.
assert_same_key noisy-1 noisy-2 downstream-of-pruned
assert_cache_hit noisy-2 downstream-of-pruned

finish
