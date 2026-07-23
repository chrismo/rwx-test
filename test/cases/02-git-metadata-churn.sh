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
#   no-git-dir HELD              -> a default clone is already immune, because
#                                   git/clone strips .git unless asked not to
#   with-git-dir-unfiltered MOVED -> preserve-git-dir: true is what destroys
#                                   cache hits on every commit
#   with-git-dir-filtered HELD    -> and `!.git/**` restores them

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/rwx.sh"

CONFIG=".rwx/cache-02-git-metadata-churn.yml"

case "${1:-compare}" in
  seed)
    start_case "02 — seeding at the current commit"
    rwx_run git-a "$CONFIG" >/dev/null
    assert_run_succeeded git-a
    for t in no-git-dir with-git-dir-unfiltered with-git-dir-filtered; do
      printf '  %-24s %s\n' "$t" "$(cache_key git-a "$t")"
    done
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
    for t in no-git-dir with-git-dir-unfiltered with-git-dir-filtered; do
      a="$(cache_key git-a "$t")"; b="$(cache_key git-b "$t")"
      if [[ "$a" == "$b" ]]; then verdict="HELD "; else verdict="MOVED"; fi
      printf '    %-24s %s  %s\n' "$t" "$verdict" "$a"
      [[ "$a" == "$b" ]] || printf '    %-24s        %s\n' "" "$b"
    done
    printf '\n'

    # A default clone carries no .git, so pure metadata churn can't touch it.
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
