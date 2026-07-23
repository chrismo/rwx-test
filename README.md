# rwx-test

Integration tests for [RWX](https://www.rwx.com) — executable claims about how
RWX actually behaves, with an emphasis on caching and build optimization.

Every test is a run definition in `.rwx/` plus a case in `test/cases/` that
starts real runs and asserts on the results. Nothing is mocked. If something
here says RWX does X, a run showed it doing X.

## Why

RWX's content-based caching is genuinely good, and it's easy to get subtly
wrong by reasoning about it instead of measuring it. Two failures we watched
happen for real, both on a live main branch:

- A filter added to *improve* cache hits silently stripped a data directory off
  disk. Every shard of the suite failed with a "file not found" that looked
  nothing like a filter problem.
- A caching change was validated locally with `rwx run`, pushed, and then
  re-executed everything anyway. There was no way to tell whether that was
  benign (CLI and push runs being separate cache populations) or a real defect
  (`.git` busting the key on every commit). **Both explanations predicted the
  same observation** — which is exactly when you stop theorizing and run an
  experiment.

## Status

Only rows marked **confirmed** have been observed. The rest are written down so
they can be settled, not because they're known.

| # | Claim | Status |
|---|---|---|
| 01 | Sibling tasks are independent cache units; no filter needed | **confirmed** |
| 02 | `.git` churn busts the cache key — but only with `preserve-git-dir: true` | **confirmed** |
| 03 | CLI-triggered and push-triggered runs share one cache | **confirmed** |
| 05 | A positive filter entry makes the filter an allowlist and deletes unlisted files from disk | **confirmed** |
| 06 | A downstream task cache-hits even when its upstream missed, if upstream output is unchanged | **confirmed** |
| 08 | `cache: false` is a per-task opt-out; siblings still cache | **confirmed** |
| 09 | Non-reproducible upstream output poisons a downstream task only when the varying bytes are inside its filter | **confirmed** |
| 10 | A task that git-clones into its workspace emits non-reproducible output via `.git/logs/HEAD`, churning downstream keys | **confirmed** |
| 07 | Tool caches make dependency installs incremental across misses | not written — needs a vault |

Plan items 04 and 05 collapsed into one: they're the same mechanism seen from
two sides, so `cache-05-filter-semantics.yml` covers both.

### Both incidents are now settled

The mystery from the second bullet above — validated locally, re-ran on push,
two explanations that predicted the same observation — resolved like this:

- **Test 03 killed the benign explanation.** CLI and push runs *do* share one
  cache. A task first executed from `rwx run` came back a `cache_hit` in a
  push-triggered run with an identical key. So "my local validation couldn't
  seed the push run" was false, and the re-execution was real.
- **Test 02 killed the leading suspect.** `.git` was never in the workspace.
  `git/clone` defaults to `preserve-git-dir: false` and has an explicit
  `cleanup-git-dir` step, so a default clone is structurally immune to commit
  churn. `.git` only busts keys when you opt into keeping it.

Which means: with a default clone, the cause was neither trigger populations
nor `.git`. It was the ordinary content of the files the filter still let
through. Worth knowing that `${{ run.dir }}` pulls in the **entire** `.rwx`
directory, so any task referencing it churns whenever any run definition
changes — a filter is required there too.

## What a test looks like

The claim goes in the definition, and the tasks assert it themselves:

```yaml
# .rwx/cache-06-downstream-hit-on-miss.yml
tasks:
  - key: write-foo
    run: |
      echo "noise: $NOISE"   # changes this task's own inputs every run
      echo foo > foo.txt     # …but always writes identical bytes
    env:
      NOISE: ${{ init.noise }}

  - key: hash-foo
    use: write-foo
    run: sha256sum foo.txt
```

The case runs it twice with different salts and asserts the interesting part —
that the *upstream* missing doesn't drag the *downstream* with it:

```sh
rwx_run noise-a "$CONFIG" --init noise=a
rwx_run noise-b "$CONFIG" --init noise=b

assert_diff_key  noise-a noise-b write-foo   # upstream inputs changed
assert_executed  noise-b write-foo           # …so it re-ran
assert_same_key  noise-a noise-b hash-foo    # downstream inputs did not
assert_cache_hit noise-b hash-foo            # …so it was reused
```

```
06 — downstream cache hit despite upstream miss
  ✓ write-foo got a new cache key across 'noise-a' and 'noise-b'
  ✓ write-foo executed in 'noise-b'
  ✓ hash-foo kept the same cache key across 'noise-a' and 'noise-b'
  ✓ hash-foo was a cache hit in 'noise-b'
```

## What's been confirmed

**Sibling isolation (01).** Two runs differing only in an init parameter that
just one task consumes: `alpha`'s cache key moved `126cefbb…` → `cfa42d85…` and
it re-executed, while `beta`'s stayed byte-identical at `d7481068…` and served
from cache. No filter involved — task separation alone is enough.

**Downstream hit on upstream miss (06).** As above. This is the property most
worth internalizing: under the key-prefix caching most CI systems use, touching
a build script invalidates everything downstream. Here it doesn't, so long as
the bytes it produces don't change.

**Filter semantics (05).** All four documented rules held, each asserted by a
task that fails the run if it doesn't:

- all entries negated → denylist; everything unmatched survives
- **any** positive entry → allowlist, and unlisted files are *removed from
  disk*, not merely excluded from the cache key
- last matching entry wins, so ordering is load-bearing
- a bare entry is an exact path — `root.txt` does not match `nested/root.txt`

The second rule is the one that breaks production branches. A filter is not a
cache-key annotation; it changes what the task can see.

**`cache: false` (08).** Per-task, not contagious. Worth pairing with the fact
that RWX doesn't detect non-determinism — a task running `date` caches like any
other and will serve a stale timestamp indefinitely. `cache: false` and
`cache: {ttl}` are the two levers.

**`.git` and `preserve-git-dir` (02).** Across an *empty* commit — new SHA and
refs, byte-identical working tree, which isolates metadata from content:

| task | clone | result |
|---|---|---|
| `no-git-dir` | default | key **held** |
| `with-git-dir-unfiltered` | `preserve-git-dir: true` | key **moved** |
| `with-git-dir-filtered` | preserved, `!.git/**` | key **held** |

Reproduced across two independent commit pairs. So `preserve-git-dir: true`
costs you a cache miss on *every commit* for every task consuming that clone,
unless you filter `.git` back out. Turn it on only when a task genuinely runs
git operations, and filter it everywhere else.

**Non-reproducible upstreams (09).** The proposed framing was "an unfiltered
upstream with non-reproducible output defeats every downstream filter." The
strong form is false. Two identical runs of a producer writing both a stable
file and `date +%s%N`:

| consumer | defense | result |
|---|---|---|
| `downstream-unfiltered` | none | key **moved**, re-executed |
| `downstream-filtered` | `filter: [stable.txt]` | key **held**, cache hit |
| `downstream-of-pruned` | none — producer pruned its own layer | key **held**, cache hit |

So volatile output poisons a consumer only when the varying bytes fall *inside*
that consumer's filter. And the third row is the lever worth reaching for:
`outputs.filesystem.filter` on the **producer** stops the poison at the source,
immunizing every consumer at once — including ones with no filter of their own.
Filtering each consumer is the same fix applied N times and forgotten on the
N+1th.

**The disguised timestamp (10).** This is the one that fools everyone, and it's
worth dwelling on. A step that installs a tool pinned to a fixed version, reads
nothing from the repo, and runs the identical command every time — you would
swear it's deterministic. It isn't, if it git-clones anything. A clone writes
`.git/logs/HEAD` with the wall clock:

```
0000…  2491d2ee…  Ubuntu <…>  1784838527 +0000  clone: from …
                              ^^^^^^^^^^ unix time, in the file's bytes
```

So the task's output layer differs on every run by exactly those bytes, and
every downstream task keyed off it churns — no downstream filter can help,
because the poison rides along in the received filesystem (test 09). Measured
across two runs of an install that clones into its workspace:

| consumer | producer | result |
|---|---|---|
| `downstream-of-naive` | clone kept its `.git` | key **moved**, re-executed |
| `downstream-of-cleaned` | `rm -rf .git` after the clone | key **held**, cache hit |

This surfaced in the wild as an `asdf plugin add` step that quietly kept a whole
test suite from ever caching. It is the *same* hazard RWX's own `git/clone`
guards against with `preserve-git-dir: false` (test 02) — re-introduced by hand,
one layer down, inside a tool installer nobody thought to suspect.

The fix is `rm -rf <clone>/.git` right after the install, and it leans on claim
06: the installer may re-run all it likes, so long as its *output bytes* are
stable, everything downstream still cache-hits.

**The general lesson.** "Deterministic" is about output bytes, not about whether
the command looks stable. Before trusting a step to cache, ask what it *writes*,
not what it *does* — embedded timestamps, build IDs, absolute paths, and git
metadata are the usual culprits, and they hide inside steps that read like pure
functions.

**CLI and push share a cache (03).** They are one content-addressed
population. This is what makes `rwx run` a legitimate way to validate a
caching change before pushing — the run you do locally really does seed the
run that a push will start.

## Gotchas found while building this

- **You can't infer a cache hit from duration.** A confirmed `cache_hit` task
  still reported `CompletedRuntimeSeconds: 9`; that clock includes layer
  assembly. Read `Status.FinishedSubStatus`.
- **`CacheKey` is a better probe than hit/miss.** A task can have a perfectly
  stable key and still execute, simply because nothing had populated it yet. To
  ask "did my edit disturb this task's inputs?", compare keys across two runs.
- **`rwx lint` doesn't validate expression contexts.** It happily passed
  `${{ run.trigger }}`, which isn't a real context and fails at runtime.
- **`rwx results` exits non-zero when the run failed** but still prints valid
  JSON on stdout — parse stdout before trusting the exit code.
- **SuperDB v0.3.0 has a recursive-`fn` scoping bug** that makes the natural
  tree walk silently wrong. Reproducer and workaround are in
  `test/lib/rwx.sh`.
- **A cache-aware test must use novel inputs, or it passes exactly once.**
  Cases 01 and 06 asserted a task `executed`; on the second run of the suite
  RWX had already seen those salts and correctly served them from cache, so
  the assertions failed for a reason unrelated to the claim. They now salt
  with a per-invocation nonce. The suite has to assume the cache remembers it.
- **`rwx run` patches uncommitted edits into the clone.** Excellent for
  iteration, but it means a dirty working tree silently converts a
  metadata-only experiment into a content experiment. Case 02 checks for a
  clean tree and an empty diff, and skips rather than reporting a wrong
  answer.

## Spend protection

This repo is public, so an outsider must not be able to make it spend.

- **No `pull_request` trigger exists anywhere in `.rwx/`.** Opening PRs — any
  number, from anywhere — starts nothing.
- **Exactly one definition can start itself**:
  `cache-03-cli-vs-push-cache.yml`, guarded by
  `if: ${{ event.git.branch == 'main' }}` and deliberately just two echo tasks,
  so a stray push to main costs seconds. It carries a push trigger only because
  the claim it tests is specifically *about* push-triggered runs.
- **Every other definition is `on: cli:` only**, and runs when a human or the
  harness deliberately starts it.

RWX additionally disables fork runs on public repos by default, and even when
enabled they must be manually started by an org member.

## Running the tests

Requires the [`rwx` CLI](https://www.rwx.com/docs) (signed in) and
[SuperDB](https://superdb.org) `super` v0.3.0 for assertions.

```sh
test/run.sh              # every self-starting case
test/run.sh 05 06        # just those
```

These start real runs and cost real compute — they're integration tests, and
the point is that they don't fake the thing they measure. Results JSON lands in
`.results/` (gitignored), so you can re-query a finished run without paying for
it twice:

```sh
source test/lib/rwx.sh && task_summary noise-b
```

That walks the whole task tree, including nested subtasks and RWX's own
`~base-image` / `~base-config` tasks. Raw `super` queries against the JSON work
too — just note that `unnest Tasks` alone sees only the top level.

Case 03 is manual in two steps, because it needs a real push:

```sh
test/cases/03-cli-vs-push-cache.sh seed   # start the CLI half
git push                                  # fires the push half
test/cases/03-cli-vs-push-cache.sh compare
```

## How assertions work

Cache behavior is invisible from inside a task — a hit means the task never
ran. It's fully visible from outside, via `rwx results <id> --json`, which
carries `CacheKey` and `Status.FinishedSubStatus` per task. `test/lib/rwx.sh`
reads that with `super` and exposes:

| helper | asks |
|---|---|
| `assert_cache_hit` | did this task reuse a prior result? |
| `assert_executed` | did it actually run? |
| `assert_same_key` / `assert_diff_key` | did an edit disturb its inputs? |
| `assert_task_succeeded` | did a self-verifying task pass? |
| `assert_log_contains` | did it observe on disk what we claim? |

## Layout

```
.rwx/                       run definitions — one claim each
test/lib/rwx.sh             assertion library (rwx results + super)
test/cases/                 one case per claim
test/run.sh                 runner
sample/                     stand-in source/docs files for churn tests
.results/                   captured run JSON (gitignored)
CLAUDE.md                   conventions and traps for agents working here
```
