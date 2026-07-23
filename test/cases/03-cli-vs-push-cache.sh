#!/usr/bin/env bash
# Claim (UNPROVEN): CLI-triggered and push-triggered runs share one content
# cache, because cache keys are content-based and the trigger is not an input.
#
# This case is different from the others: it cannot start both halves itself.
# A push run has to come from an actual push to main. So the flow is:
#
#   1. ./test/cases/03-cli-vs-push-cache.sh seed     # starts the CLI run
#   2. push any commit to main                       # fires the push trigger
#   3. ./test/cases/03-cli-vs-push-cache.sh compare  # reads both, asserts
#
# `compare` finds the newest push-triggered run of this definition rather than
# taking a run ID, so step 2 can be any ordinary commit.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/rwx.sh"

CONFIG=".rwx/cache-03-cli-vs-push-cache.yml"
DEFINITION=".rwx/cache-03-cli-vs-push-cache.yml"

case "${1:-compare}" in
  seed)
    start_case "03 — seeding the CLI half"
    rwx_run trigger-cli "$CONFIG" >/dev/null
    assert_run_succeeded trigger-cli
    printf '  seeded. cache key for constant: %s\n' "$(cache_key trigger-cli constant)"
    printf '  now push a commit to main, then re-run with: compare\n'
    finish
    ;;

  compare)
    start_case "03 — do CLI and push runs share a cache?"

    if [[ ! -f "$RESULTS_DIR/trigger-cli.json" ]]; then
      printf '  no CLI baseline yet — run with `seed` first\n' >&2
      exit 1
    fi

    push_id="$(rwx runs list --definition "$DEFINITION" --limit 50 --json 2>/dev/null \
      | super -f line -c '
          unnest Runs
          | where Trigger == "github.push"
          | head 1
          | values ID
        ' - 2>/dev/null || true)"

    if [[ -z "$push_id" ]]; then
      printf '  no push-triggered run of %s found yet.\n' "$DEFINITION"
      printf '  push a commit to main and re-run.\n'
      exit 1
    fi

    rwx results "$push_id" --json > "$RESULTS_DIR/trigger-push.json" 2>/dev/null || true

    assert_run_succeeded trigger-push

    # The decisive pair. If the keys match but the push run still executed,
    # the populations are separate and every "I validated it locally" claim
    # about caching is unverifiable from a CLI run alone.
    assert_same_key trigger-cli trigger-push constant
    assert_cache_hit trigger-push constant

    finish
    ;;

  *)
    printf 'usage: %s [seed|compare]\n' "$0" >&2
    exit 1
    ;;
esac
