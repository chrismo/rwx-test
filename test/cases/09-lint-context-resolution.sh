#!/usr/bin/env bash
# Demonstrates that `rwx lint` checks syntax, not whether an expression resolves
# to something real. The config references `run.trigger`, which isn't a field in
# the `run` context (it holds only dir, id, mint-dir). Lint passes it; the run
# fails at expression resolution.
#
# A clean lint is necessary, not sufficient — an expression typo reaches you
# only at run time. This is why the repo validates with `rwx run`, not lint.
#
# The run is expected to FAIL; that failure is the demonstration. Idempotent —
# resolution fails before any task caches, so it re-fails identically.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/rwx.sh"

CONFIG=".rwx/lint-09-context-resolution.yml"

start_case "09 — lint passes, runtime rejects an unresolved context"

# Lint is happy with the bad expression.
assert_lint_clean "$CONFIG"

# The run is not.
rwx_run bad-context "$CONFIG" >/dev/null
assert_run_failed bad-context

# And it fails for the right reason — context resolution, not something else.
assert_task_message_contains bad-context uses-a-bad-context \
  "\`trigger\` does not exist in the \`run\` context"

finish
