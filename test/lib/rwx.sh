#!/usr/bin/env bash
# Assertion library for RWX integration tests.
#
# The whole premise: cache behavior is not observable from *inside* a task — a
# cache hit means the task never ran. It is observable from outside, via
# `rwx results <id> --json`, which carries per-task `CacheKey` and
# `Status.FinishedSubStatus`. Everything here reads that payload with `super`.
#
# Two distinct assertions, and the difference matters:
#
#   assert_cache_hit   — did this task reuse a prior result *in this run*?
#   assert_same_key    — did this task's inputs hash identically across runs?
#
# `assert_same_key` is the stronger, cheaper signal. A task can have a stable
# cache key and still execute (nothing had run it before yet), so a missing hit
# is not proof of a busted key. When you want to know whether an edit disturbed
# a task's inputs, compare keys.
#
# Do NOT infer cache hits from task duration. An observed cache_hit task still
# reported CompletedRuntimeSeconds: 9 — that clock includes layer assembly.

set -euo pipefail

RWX_TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESULTS_DIR="${RWX_TEST_RESULTS_DIR:-$RWX_TEST_ROOT/.results}"
mkdir -p "$RESULTS_DIR"

_pass=0
_fail=0
_case=""

# ---------------------------------------------------------------------------
# Running
# ---------------------------------------------------------------------------

# rwx_run <label> <config> [extra rwx run args...]
# Starts a run, waits for it, saves results JSON to $RESULTS_DIR/<label>.json.
# Echoes the run ID.
rwx_run() {
  local label="$1" config="$2"
  shift 2

  local out
  # `rwx run` exits non-zero when the run fails; we still want its output, and
  # a failed run is a legitimate expectation in some tests.
  out="$(rwx run "$config" --wait "$@" 2>&1)" || true

  local run_id
  run_id="$(printf '%s' "$out" | sed -n 's#.*/runs/\([0-9a-f]\{16,\}\).*#\1#p' | head -1)"

  if [[ -z "$run_id" ]]; then
    printf 'could not extract a run ID from `rwx run %s`:\n%s\n' "$config" "$out" >&2
    return 1
  fi

  # `rwx results` also exits non-zero on a failed run while still printing JSON,
  # so parse stdout first and only complain if it is not JSON (same reasoning as
  # crux's internal/rwx/cli.go).
  rwx results "$run_id" --json >"$RESULTS_DIR/$label.json" 2>/dev/null || true
  if ! super -f line -c 'count()' "$RESULTS_DIR/$label.json" >/dev/null 2>&1; then
    printf 'rwx results %s did not return parseable JSON\n' "$run_id" >&2
    return 1
  fi

  printf '%s' "$run_id"
}

_json() { printf '%s/%s.json' "$RESULTS_DIR" "$1"; }

# ---------------------------------------------------------------------------
# Reading the results payload
# ---------------------------------------------------------------------------
#
# Tasks nest recursively under Subtasks (parallel tasks, embedded runs, and
# packages all produce children), so walking only the top-level Tasks array
# silently misses them. This is the superdb equivalent of jq's
# recurse(.Subtasks[]?).
#
# The tree also contains RWX's own system tasks (~base-image, ~base-config).
# They are real cache participants and worth seeing, but they are not yours.
#
# Why fork-with-fixed-depth instead of a recursive `fn`:
#
#   SuperDB v0.3.0 has a scoping bug that makes the obvious recursive version
#   silently wrong. Given
#
#     fn descend(t): [t, ...[unnest t.Subtasks | unnest descend(this)]]
#     values descend({Key:"root", Subtasks:[{Key:"kid", Subtasks:[]}]})
#
#   it returns [kid, kid, kid] — the parameter `t` in the leading position is
#   shadowed by the inner subquery's `this`, so the parent is dropped and the
#   children are duplicated. Splitting the subquery into a second function does
#   not help. The non-recursive `this` form below evaluates correctly.
#
#   The cost is a fixed depth. Three levels covers every tree RWX has produced
#   here (a 4th `unnest` errors with `no such field "Subtasks"`, because
#   depth-3 records don't carry the field). If a future run nests deeper,
#   add another branch — it will not silently truncate, `assert_*` will just
#   fail to find the key.

_FLATTEN='
unnest Tasks
| fork
  ( values this )
  ( unnest Subtasks )
  ( unnest Subtasks | unnest Subtasks )
'

# task_field <label> <task-key> <field-expr>
task_field() {
  super -f line -c "$_FLATTEN | where Key == '$2' | values $3" "$(_json "$1")"
}

# cache_key <label> <task-key>
cache_key() { task_field "$1" "$2" 'CacheKey'; }

# finished_substatus <label> <task-key> -> cache_hit | executed | ...
finished_substatus() { task_field "$1" "$2" 'Status.FinishedSubStatus'; }

# task_messages <label> <task-key> — the text of every Message on a task.
# Runtime errors (e.g. a bad expression context) land here as Type: user_error.
task_messages() {
  super -f line -c "$_FLATTEN | where Key == '$2' | unnest Messages | values Message" "$(_json "$1")"
}

# task_summary <label> — human-readable table of every task in the run
task_summary() {
  # CacheKey is null for package tasks, and null is not sliceable — so no
  # truncating it here without a guard.
  super -f table -c "$_FLATTEN | values {
    Key,
    Type: TaskType,
    State: Status.FinishedSubStatus,
    Result: Status.Result,
    CacheKey
  }" "$(_json "$1")"
}

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

start_case() { _case="$1"; printf '\n\033[1m%s\033[0m\n' "$1"; }

_ok()   { _pass=$((_pass + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
_bad()  { _fail=$((_fail + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; printf '      %s\n' "$2"; }

# assert_run_succeeded <label>
assert_run_succeeded() {
  local got
  got="$(super -f line -c 'values ResultStatus' "$(_json "$1")")"
  [[ "$got" == "succeeded" ]] \
    && _ok "run '$1' succeeded" \
    || _bad "run '$1' succeeded" "got ResultStatus=$got"
}

# assert_run_failed <label> — for tests whose point is that a task breaks
assert_run_failed() {
  local got
  got="$(super -f line -c 'values ResultStatus' "$(_json "$1")")"
  [[ "$got" == "failed" ]] \
    && _ok "run '$1' failed as expected" \
    || _bad "run '$1' failed as expected" "got ResultStatus=$got"
}

# assert_task_succeeded <label> <task-key>
# For configs whose tasks assert their own expectations with `test` — the task
# result IS the assertion. Fails loudly if the key is absent, so a typo'd or
# renamed task key can't quietly pass.
assert_task_succeeded() {
  local got; got="$(task_field "$1" "$2" 'Status.Result')"
  if [[ -z "$got" ]]; then
    _bad "$2 succeeded in '$1'" "no task with that key in the run"
  elif [[ "$got" == "succeeded" ]]; then
    _ok "$2 succeeded in '$1'"
  else
    _bad "$2 succeeded in '$1'" "Status.Result=$got"
  fi
}

# assert_cache_hit <label> <task-key>
assert_cache_hit() {
  local got; got="$(finished_substatus "$1" "$2")"
  [[ "$got" == "cache_hit" ]] \
    && _ok "$2 was a cache hit in '$1'" \
    || _bad "$2 was a cache hit in '$1'" "FinishedSubStatus=$got"
}

# assert_executed <label> <task-key>
assert_executed() {
  local got; got="$(finished_substatus "$1" "$2")"
  [[ "$got" == "executed" ]] \
    && _ok "$2 executed in '$1'" \
    || _bad "$2 executed in '$1'" "FinishedSubStatus=$got"
}

# assert_same_key <label-a> <label-b> <task-key>
assert_same_key() {
  local a b; a="$(cache_key "$1" "$3")"; b="$(cache_key "$2" "$3")"
  [[ -n "$a" && "$a" == "$b" ]] \
    && _ok "$3 kept the same cache key across '$1' and '$2'" \
    || _bad "$3 kept the same cache key across '$1' and '$2'" "$a != $b"
}

# assert_diff_key <label-a> <label-b> <task-key>
assert_diff_key() {
  local a b; a="$(cache_key "$1" "$3")"; b="$(cache_key "$2" "$3")"
  [[ -n "$a" && -n "$b" && "$a" != "$b" ]] \
    && _ok "$3 got a new cache key across '$1' and '$2'" \
    || _bad "$3 got a new cache key across '$1' and '$2'" "both were $a"
}

# assert_log_contains <run-id> <task-key> <substring>
# For claims about what a task actually saw on disk — e.g. whether a filter
# stripped a file out from under it.
assert_log_contains() {
  local dir; dir="$(mktemp -d)"
  rwx logs "$1" --task "$2" --output "$dir" >/dev/null 2>&1 || true
  if grep -qrF -- "$3" "$dir" 2>/dev/null; then
    _ok "$2 logged '$3'"
  else
    _bad "$2 logged '$3'" "not found in task logs"
  fi
  rm -rf "$dir"
}

# assert_log_missing <run-id> <task-key> <substring>
assert_log_missing() {
  local dir; dir="$(mktemp -d)"
  rwx logs "$1" --task "$2" --output "$dir" >/dev/null 2>&1 || true
  if grep -qrF -- "$3" "$dir" 2>/dev/null; then
    _bad "$2 did not log '$3'" "but it did"
  else
    _ok "$2 did not log '$3'"
  fi
  rm -rf "$dir"
}

# assert_lint_clean <config> — `rwx lint` reports no problems (exit 0).
assert_lint_clean() {
  if rwx lint "$1" >/dev/null 2>&1; then
    _ok "rwx lint clean: $1"
  else
    _bad "rwx lint clean: $1" "lint reported problems"
  fi
}

# assert_task_message_contains <label> <task-key> <substring>
# Asserts a task's runtime Messages carry the given text — for proving a task
# failed for the specific reason claimed, not just that it failed.
assert_task_message_contains() {
  if task_messages "$1" "$2" | grep -qF -- "$3"; then
    _ok "$2 reported '$3'"
  else
    _bad "$2 reported '$3'" "not found in task messages"
  fi
}

finish() {
  printf '\n\033[1m%d passed, %d failed\033[0m\n' "$_pass" "$_fail"
  [[ "$_fail" -eq 0 ]]
}
