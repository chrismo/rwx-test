# rwx-test

Working examples that demonstrate how [RWX](https://www.rwx.com) build-config
features behave. Each example is a run definition in `.rwx/` plus a case in
`test/cases/` that starts a real run and checks the result. Nothing is mocked —
each one shows actual RWX behavior, observed from a run.

## Field notes

- **Split work into small tasks.** They cache independently, so an edit re-runs only what depends on it — no filter required for that alone ([01](#ex-01)).
- **Judge caching by output bytes, not effort.** Rewriting a task's script costs nothing downstream as long as the bytes it produces are unchanged — "deterministic" is about the bytes out, not the command in ([06](#ex-06)).
- **Hunt hidden non-determinism, and fix it at the producer.** Timestamps, build IDs, and absolute paths baked into a task's output churn every downstream key. Drop the volatile files from the producer's own output layer with `outputs.filesystem.filter` — that immunizes every consumer at once, better than filtering each one ([09](#ex-09)).
- **Filter a task that takes a big input but needs a slice** — the repo clone, or the whole `.rwx` dir pulled in by `${{ run.dir }}`. Without one, any unrelated change busts the key.
- **Remember a filter deletes files, not just key entries.** One positive entry flips it to an allowlist and removes everything unlisted from disk ([05](#ex-05)). Use `!pattern` negations when you mean "everything except".
- **Leave `preserve-git-dir` off, and strip stray `.git` dirs.** A `.git` directory carries wall-clock timestamps (refs, `.git/logs/HEAD`) that change on every commit and clone, so it busts the cache. Keep it off unless a task runs git commands — and if it needs it, filter `['!.git/**']` ([02](#ex-02)). Same trap when a step git-clones something itself, like a tool installer: `rm -rf <clone>/.git` after ([10](#ex-10)).
- **Opt out on purpose, not by accident.** `cache: false` forces a re-run and `cache: {ttl: …}` refreshes on a schedule — for tasks non-deterministic by design ([08](#ex-08)).
- **Iterate with `rwx run` — no commit needed.** It patches your local uncommitted edits into the run ([13](#ex-13)), so you can tighten a config against real infrastructure in a tight loop. A clean `rwx lint` isn't proof; only a run resolves expressions ([11](#ex-11)).
- **Diagnose with the right signal.** `Status.FinishedSubStatus` (`cache_hit` vs `executed`) and `CacheKey` compared across two runs — never duration, which is nonzero even on a hit ([12](#ex-12)).

## Examples

Each row is demonstrated by a real run unless noted. Detail lives in each
definition's header comment.

| # | Example | What it shows |
|---|---|---|
| <a id="ex-01"></a>[01](.rwx/cache-01-native-task-isolation.yml) | Sibling tasks cache independently | Changing one task's inputs doesn't re-run a sibling — no filter needed. |
| <a id="ex-02"></a>[02](.rwx/cache-02-git-metadata-churn.yml) | `.git` vs `preserve-git-dir` | A default clone strips `.git`. With `preserve-git-dir: true`, every consumer misses on each commit unless you `filter: ['!.git/**']`. |
| <a id="ex-03"></a>[03](.rwx/cache-03-cli-vs-push-cache.yml) | CLI and push share one cache | `rwx run` locally seeds the run a push will start — same content-addressed pool. |
| <a id="ex-05"></a>[05](.rwx/cache-05-filter-semantics.yml) | Filters change what's *on disk* | One positive entry makes a filter an allowlist and removes unlisted files. Last match wins; a bare entry is an exact path. |
| <a id="ex-06"></a>[06](.rwx/cache-06-downstream-hit-on-miss.yml) | Downstream hits on upstream miss | A task cache-hits even when its upstream re-ran, as long as the upstream's *output bytes* are unchanged. |
| <a id="ex-08"></a>[08](.rwx/cache-08-cache-false.yml) | `cache: false` is per-task | Opts one task out; siblings still cache. |
| <a id="ex-09"></a>[09](.rwx/cache-09-nonreproducible-upstream.yml) | Non-reproducible upstream | Affects a consumer only when the volatile bytes are inside *its* filter. `outputs.filesystem.filter` on the producer covers every consumer at once. |
| <a id="ex-10"></a>[10](.rwx/cache-10-disguised-clone-timestamp.yml) | Disguised non-determinism | A step that git-clones (e.g. `asdf plugin add`) writes a wall-clock timestamp into `.git/logs/HEAD`, so its output changes each run though the command looks fixed. `rm -rf <clone>/.git` after. |
| <a id="ex-11"></a>[11](.rwx/lint-11-context-resolution.yml) | Lint vs runtime | `rwx lint` checks syntax, not whether an expression resolves. A reference to a nonexistent context passes lint and fails at run time. |
| <a id="ex-12"></a>[12](.rwx/cache-12-duration-not-a-hit-signal.yml) | Duration isn't a hit signal | A cache-hit task still reports nonzero `CompletedRuntimeSeconds` (it includes layer assembly). Read `Status.FinishedSubStatus`, not the clock. |
| <a id="ex-13"></a>[13](.rwx/rwx-run-13-local-patch.yml) | `rwx run` sends local edits | Uncommitted, unpushed changes are patched into the clone — the basis for local iteration. (Gitignored files are excluded.) |
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
