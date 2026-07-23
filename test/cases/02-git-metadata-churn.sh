#!/usr/bin/env bash
# Claim: `.git` metadata busts the cache key of any task that consumes a clone
# without filtering it out.
#
# Isolating `.git` requires two runs whose working trees are byte-identical but
# whose commits differ — otherwise a changed source file is a confound and you
# can't tell which input moved the key. An EMPTY COMMIT gives exactly that: new
# SHA, new refs, new reflog, identical files.
#
#   1. test/cases/02-git-metadata-churn.sh seed
#   2. git commit --allow-empty -m "churn" && git push
#   3. test/cases/02-git-metadata-churn.sh compare
#
# Reading the result:
#   unfiltered key MOVED + excludes-git key HELD  -> .git is the culprit,
#     and every `use: code` task wants `!.git/**` in its filter.
#   both HELD -> .git does not participate; the peer's re-execution had some
#     other cause and this whole line of suspicion is dead.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/rwx.sh"

CONFIG=".rwx/cache-02-git-metadata-churn.yml"

case "${1:-compare}" in
  seed)
    start_case "02 — seeding at the current commit"
    rwx_run git-a "$CONFIG" >/dev/null
    assert_run_succeeded git-a
    printf '  unfiltered:   %s\n' "$(cache_key git-a unfiltered)"
    printf '  excludes-git: %s\n' "$(cache_key git-a excludes-git)"
    printf '  source-only:  %s\n' "$(cache_key git-a source-only)"
    printf '\n  now: git commit --allow-empty -m "churn" && git push\n'
    printf '  then re-run with: compare\n'
    finish
    ;;

  compare)
    start_case "02 — does .git churn bust the cache key?"

    if [[ ! -f "$RESULTS_DIR/git-a.json" ]]; then
      printf '  no baseline — run with `seed` first\n' >&2
      exit 1
    fi

    rwx_run git-b "$CONFIG" >/dev/null
    assert_run_succeeded git-b

    printf '\n  cache keys across an empty commit:\n'
    for t in unfiltered excludes-git source-only; do
      a="$(cache_key git-a "$t")"; b="$(cache_key git-b "$t")"
      if [[ "$a" == "$b" ]]; then verdict="HELD"; else verdict="MOVED"; fi
      printf '    %-14s %s  %s\n' "$t" "$verdict" "$a"
      [[ "$a" == "$b" ]] || printf '                   %s\n' "$b"
    done
    printf '\n'

    # Tasks that filter .git out must be immune to a pure-metadata commit.
    assert_same_key git-a git-b excludes-git
    assert_same_key git-a git-b source-only

    finish
    ;;

  *)
    printf 'usage: %s [seed|compare]\n' "$0" >&2
    exit 1
    ;;
esac
