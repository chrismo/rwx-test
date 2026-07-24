# rwx-test

Working examples that demonstrate how [RWX](https://www.rwx.com) build-config
features behave. Each example is a run definition in `.rwx/` plus a case in
`test/cases/` that starts a real run and checks the result. Nothing is mocked —
each one shows actual RWX behavior, observed from a run.

## Field notes

Distilled from the examples — each is something a run actually showed, not
folklore. The number points to the example that demonstrates it.

- **Split work into small tasks.** They cache independently, so an edit re-runs only what depends on it — no filter required for that alone (01).
- **Judge caching by output bytes, not effort.** Rewriting a task's script costs nothing downstream as long as the bytes it produces are unchanged (06). "Deterministic" means same bytes out, not same command in (10).
- **Hunt hidden non-determinism before blaming the cache.** Timestamps, build IDs, absolute paths, and especially git metadata churn output every run — a clone stamps a wall-clock time into `.git/logs/HEAD` (09, 10). If a step git-clones, `rm -rf <clone>/.git` after it.
- **Fix churn at the producer, not each consumer.** `outputs.filesystem.filter` drops volatile files from a task's output layer, immunizing everything downstream at once — beats filtering each consumer one by one (09).
- **Filter a task that takes a big input but needs a slice** — the repo clone, or the whole `.rwx` dir pulled in by `${{ run.dir }}`. Without one, any unrelated change busts the key.
- **Remember a filter deletes files, not just key entries.** One positive entry flips it to an allowlist and removes everything unlisted from disk (05). Use `!pattern` negations when you mean "everything except".
- **Leave `preserve-git-dir` off unless a task runs git commands.** On, it re-stamps `.git` every commit and busts the key; if you truly need it, add `filter: ['!.git/**']` (02).
- **Opt out on purpose, not by accident.** `cache: false` forces a re-run and `cache: {ttl: …}` refreshes on a schedule — for tasks non-deterministic by design (08).
- **Iterate with `rwx run` — no commit needed.** It patches your local uncommitted edits into the run (13), so you can tighten a config against real infrastructure in a tight loop. A clean `rwx lint` isn't proof; only a run resolves expressions (11).
- **Diagnose with the right signal.** `Status.FinishedSubStatus` (`cache_hit` vs `executed`) and `CacheKey` compared across two runs — never duration, which is nonzero even on a hit (12).

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
| 12 | Duration isn't a hit signal | A cache-hit task still reports nonzero `CompletedRuntimeSeconds` (it includes layer assembly). Read `Status.FinishedSubStatus`, not the clock. |
| 13 | `rwx run` sends local edits | Uncommitted, unpushed changes are patched into the clone — the basis for local iteration. (Gitignored files are excluded.) |
| 07 | Tool caches (incremental installs) | *not written — needs a vault* |

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
