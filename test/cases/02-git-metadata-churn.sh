#!/usr/bin/env bash
# Claim: `.git` metadata busts the cache key of a task that consumes a clone
# with `preserve-git-dir: true` — and only then.
#
# Isolating metadata requires two runs whose working trees are byte-identical
# but whose commits differ, otherwise a changed file is a confound and you
# cannot tell which input moved the key. An EMPTY COMMIT gives exactly that:
# new SHA, new refs, new reflog, identical content.
#
#   1. test/cases/02-git-metadata-churn.sh seed
#   2. git commit --allow-empty -m "churn" && git push
#   3. test/cases/02-git-metadata-churn.sh compare
#
# This case is stateful and two-phase, so `compare` verifies its own
# preconditions and SKIPS rather than reporting a bogus result. `rwx run`
# patches uncommitted local edits into the clone, so a dirty tree silently
# turns a metadata experiment into a content experiment — which is precisely
# the mistake that produces confident, wrong conclusions.
#
# Reading the result:
#   no-git-dir HELD               -> a default clone is already immune; the
#                                    package strips .git unless asked not to
#   with-git-dir-unfiltered MOVED -> preserve-git-dir: true is what destroys
#                                    cache hits, on every single commit
#   with-git-dir-filtered HELD    -> and `!.git/**` restores them

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/rwx.sh"

CONFIG=".rwx/cache-02-git-metadata-churn.yml"
SEED_REF="$RESULTS_DIR/git-a.commit"

skip() { printf '\n\033[33m— 02 skipped:\033[0m %s\n' "$1"; exit 0; }

case "${1:-compare}" in
  seed)
    start_case "02 — seeding at the current commit"
    [[ -z "$(git status --porcelain)" ]] \
      || skip "working tree is dirty; commit or stash before seeding"

    rwx_run git-a "$CONFIG" >/dev/null
    assert_run_succeeded git-a
    git rev-parse HEAD > "$SEED_REF"

    for t in no-git-dir with-git-dir-unfiltered with-git-dir-filtered; do
      printf '  %-24s %s\n' "$t" "$(cache_key git-a "$t")"
    done
    printf '\n  seeded at %s\n' "$(git rev-parse --short HEAD)"
    printf '  now: git commit --allow-empty -m "churn" && git push\n'
    printf '  then re-run with: compare\n'
    finish
    ;;

  compare)
    start_case "02 — does .git churn bust the cache key?"

    [[ -f "$RESULTS_DIR/git-a.json" && -f "$SEED_REF" ]] \
      || skip "no baseline — run \`$0 seed\` first"

    seed_sha="$(cat "$SEED_REF")"
    head_sha="$(git rev-parse HEAD)"

    # Each precondition below, if violated, would silently convert this into a
    # different experiment rather than an invalid one — so check, don't assume.
    [[ -z "$(git status --porcelain)" ]] \
      || skip "working tree is dirty; rwx run would patch those edits into the clone, changing content instead of only metadata"

    [[ "$seed_sha" != "$head_sha" ]] \
      || skip "HEAD is still the seed commit; make an empty commit and push first"

    [[ -z "$(git diff --name-only "$seed_sha" "$head_sha")" ]] \
      || skip "files changed between $(git rev-parse --short "$seed_sha") and $(git rev-parse --short "$head_sha"); only an EMPTY commit isolates .git metadata"

    rwx_run git-b "$CONFIG" >/dev/null
    assert_run_succeeded git-b

    printf '\n  cache keys across an empty commit (%s..%s):\n' \
      "$(git rev-parse --short "$seed_sha")" "$(git rev-parse --short "$head_sha")"
    for t in no-git-dir with-git-dir-unfiltered with-git-dir-filtered; do
      a="$(cache_key git-a "$t")"; b="$(cache_key git-b "$t")"
      if [[ "$a" == "$b" ]]; then verdict="HELD "; else verdict="MOVED"; fi
      printf '    %-24s %s  %s\n' "$t" "$verdict" "$a"
      [[ "$a" == "$b" ]] || printf '    %-24s        %s\n' "" "$b"
    done
    printf '\n'

    # A default clone carries no .git, so pure metadata churn cannot touch it.
    assert_same_key git-a git-b no-git-dir

    # Preserving .git exposes the task to every commit...
    assert_diff_key git-a git-b with-git-dir-unfiltered

    # ...and filtering it back out restores immunity.
    assert_same_key git-a git-b with-git-dir-filtered

    finish
    ;;

  *)
    printf 'usage: %s [seed|compare]\n' "$0" >&2
    exit 1
    ;;
esac
