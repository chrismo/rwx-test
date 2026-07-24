# rwx-test

Working examples that demonstrate how [RWX](https://www.rwx.com) build-config
features behave. Each example is a run definition in `.rwx/` plus a case in
`test/cases/` that starts a real run and checks the result. Nothing is mocked —
each one shows actual RWX behavior, observed from a run.

## Examples

Each row is demonstrated by a real run unless noted. Detail lives in each
definition's header comment.

| # | Example | What it shows |
|---|---|---|
| 01 | Sibling tasks cache independently | Changing one task's inputs doesn't re-run a sibling — no filter needed. |
| 02 | `.git` vs `preserve-git-dir` | A default clone strips `.git`. With `preserve-git-dir: true`, every consumer misses on each commit unless you `filter: ['!.git/**']`. |
| 03 | CLI and push share one cache | `rwx run` locally seeds the run a push will start — same content-addressed pool. |
| 05 | Filters change what's *on disk* | One positive entry makes a filter an allowlist and removes unlisted files. Last match wins; a bare entry is an exact path. |
| 06 | Downstream hits on upstream miss | A task cache-hits even when its upstream re-ran, as long as the upstream's *output bytes* are unchanged. |
| 08 | `cache: false` is per-task | Opts one task out; siblings still cache. |
| 09 | Non-reproducible upstream | Affects a consumer only when the volatile bytes are inside *its* filter. `outputs.filesystem.filter` on the producer covers every consumer at once. |
| 10 | Disguised non-determinism | A step that git-clones (e.g. `asdf plugin add`) writes a wall-clock timestamp into `.git/logs/HEAD`, so its output changes each run though the command looks fixed. `rm -rf <clone>/.git` after. |
| 11 | Lint vs runtime | `rwx lint` checks syntax, not whether an expression resolves. A reference to a nonexistent context passes lint and fails at run time. |
| 07 | Tool caches (incremental installs) | *not written — needs a vault* |

## Traps hit while building this

- Cache hits aren't visible from duration — a `cache_hit` still reports runtime. Read `Status.FinishedSubStatus`.
- Comparing `CacheKey` across two runs beats hit/miss: a stable key can still execute if nothing populated it yet.
- `rwx lint` doesn't validate expression contexts (`${{ run.trigger }}` passed lint, failed at runtime).
- `rwx results` exits non-zero on a failed run but still prints valid JSON — parse stdout first.
- Cache-aware tests need novel inputs each run (nonce salts), or they pass exactly once.
- `rwx run` patches uncommitted edits into the clone — a dirty tree silently changes the experiment.
- SuperDB v0.3.0 recursive-`fn` scoping bug — reproducer + workaround in `test/lib/rwx.sh`.

## Running

Needs the [`rwx` CLI](https://www.rwx.com/docs) (signed in) and
[SuperDB](https://superdb.org) `super` v0.3.0.

```sh
test/run.sh            # all self-starting cases
test/run.sh 05 06      # by number
```

Cases 02 and 03 are two-step (they need a real commit/push); see their headers.
Run JSON lands in `.results/` (gitignored) — re-query without re-running:
`source test/lib/rwx.sh && task_summary <label>`.

## Layout

```
.rwx/            run definitions — one edge each, claim in the header
test/cases/      one case per edge
test/lib/rwx.sh  assertion library (rwx results --json | super)
test/run.sh      runner
CLAUDE.md        conventions and traps for agents working here
```
