#!/usr/bin/env bash
# Demonstrates that `rwx run` patches local uncommitted changes into the clone:
# an untracked file, never committed or pushed, shows up in the run.
#
# The case writes a fresh token into an untracked marker at a non-ignored path
# (gitignored files are excluded from the patch), runs a config that clones the
# repo and cats the marker, and proves the token reached the clone via the task
# log. The marker is removed on exit.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/rwx.sh"

CONFIG=".rwx/rwx-run-11-local-patch.yml"
MARKER="$RWX_TEST_ROOT/local-edit-probe.txt"
TOKEN="local-only-$(date +%s)-$RANDOM"

cleanup() { rm -f "$MARKER"; }
trap cleanup EXIT

start_case "11 — rwx run patches local uncommitted edits into the clone"

# An untracked file that exists ONLY in the working tree — never committed.
printf '%s\n' "$TOKEN" > "$MARKER"

run_id="$(rwx_run local-patch "$CONFIG")"
assert_run_succeeded local-patch

# The exact unpushed bytes appear in the clone the run saw.
assert_log_contains "$run_id" show-local-marker "$TOKEN"

finish
