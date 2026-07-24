#!/usr/bin/env bash
# Claim: a task that git-clones into its workspace emits non-reproducible
# output and churns every downstream key — even when the step looks entirely
# deterministic (install a pinned tool, read nothing from the repo).
#
# The disguised form of test 07. The volatile byte is `.git/logs/HEAD`, which a
# clone writes with the wall clock. Found in the wild as an `asdf plugin add`
# step whose reinstall silently defeated every downstream filter.
#
# Caveat: the hermetic seed commit also stamps a wall-clock date into the commit
# object, so the naive output has two volatile sources, not the reflog alone.
# That is fine for the assertions here (they prove "a kept .git churns
# downstream"); it just means this repro does not isolate the reflog byte the
# way the real pinned-tool incident did.
#
# Both producers are cache: false, so they re-execute every run. The naive one
# clones fresh each time (new timestamp) and its consumer's key MOVES; the
# cleaned one strips the .git, so its output is byte-stable and its consumer
# HOLDS and cache-hits. Idempotent by construction — no salt needed.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/rwx.sh"

CONFIG=".rwx/cache-08-disguised-clone-timestamp.yml"

start_case "08 — disguised non-determinism: a clone's reflog timestamp"

rwx_run clone-1 "$CONFIG" >/dev/null
rwx_run clone-2 "$CONFIG" >/dev/null

assert_run_succeeded clone-1
assert_run_succeeded clone-2

# The trap: a "deterministic" install poisons its consumer, every run.
assert_diff_key clone-1 clone-2 downstream-of-naive
assert_executed clone-2 downstream-of-naive

# The fix: strip the .git the install created, and the consumer stabilizes —
# no filter on the consumer, per confirmed claim 05.
assert_same_key clone-1 clone-2 downstream-of-cleaned
assert_cache_hit clone-2 downstream-of-cleaned

finish
