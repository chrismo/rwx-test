# Working in this repo

Each example demonstrates real RWX behavior, observed from an actual run. Keep
it that way: if you can't show it with `rwx run`, don't state it as fact.

When you catch yourself reasoning about what RWX *would* do, run it instead.

## Spend discipline (public repo)

- **Never add a `pull_request` trigger** to any definition. Opening PRs must
  start nothing.
- **New definitions get `on: cli:` only**, unless the example is specifically
  about a different trigger.
- A self-starting trigger needs human approval, must be guarded
  (`if: ${{ event.git.branch == 'main' }}`), and kept trivial.
- Today only `.rwx/cache-03-cli-vs-push-cache.yml` self-starts. **Pushing to
  main fires it** — say so when you propose a push.

## Before answering anything about RWX

Load the `rwx` skill and `rwx docs pull` the relevant page. Don't answer from
memory — recalled RWX syntax has been wrong here, and `rwx lint` doesn't catch
every error (see traps). `rwx docs pull /migrating/rwx-reference` is the full
reference; `rwx docs search "<query>"` finds specific pages.

## Tooling

- **SuperDB (`super`), not `jq`**, for JSON. The MCP server (`mcp__superdb__*`)
  serves version-matched docs — call `super_help expert` before non-trivial
  SuperSQL. It's neither jq nor quite SQL; the old Zed/zq syntax is incompatible.
- `rwx` CLI must be signed in (`rwx whoami`).

## Adding an example

1. Write `.rwx/cache-NN-slug.yml`, one behavior per definition, with a header
   comment stating what it demonstrates and how.
2. Prefer **self-verifying tasks** — `test` inside the `run` script, so the task
   fails the run when the behavior differs (see `cache-05-filter-semantics.yml`).
3. Use **cross-run assertions** for cache keys or hits, which aren't observable
   from inside a task (see `cache-06-downstream-hit-on-miss.yml`).
4. Vary inputs with `--init` salts, not file edits between runs.
5. **Salt with a per-invocation nonce** (`NONCE="$(date +%s)-$RANDOM"`) whenever
   a case asserts a task `executed` — a fixed salt cache-hits on the second run
   and the assertion fails for the wrong reason.
6. Stateful/two-phase cases **verify preconditions and `skip` (exit 0)** rather
   than fail, since a violated precondition usually yields a plausible wrong
   answer.
7. Write `test/cases/NN-slug.sh` sourcing `test/lib/rwx.sh` (`test/run.sh NN`
   matches the numeric prefix).
8. `rwx lint .rwx/`, then **run it twice** — non-idempotent assertions only
   surface on the second pass.

## Harness API (`test/lib/rwx.sh`)

```sh
rwx_run <label> <config> [rwx run args...]   # runs, waits, saves .results/<label>.json, echoes run id
cache_key <label> <task>                     # the CacheKey SHA
finished_substatus <label> <task>            # cache_hit | executed
task_summary <label>                         # readable table of the whole tree

assert_run_succeeded / assert_run_failed <label>
assert_task_succeeded <label> <task>
assert_cache_hit / assert_executed <label> <task>
assert_same_key / assert_diff_key <label-a> <label-b> <task>
assert_log_contains / assert_log_missing <run-id> <task> <substring>
finish                                       # prints tally, exits nonzero on failure
```

Run JSON persists in `.results/` (gitignored) — re-query instead of re-running:
`source test/lib/rwx.sh && task_summary <label>`. `task_summary` applies
`_FLATTEN`; a bare `unnest Tasks` query sees only top-level tasks.

## Traps that have already bitten

- **`rwx lint` doesn't validate expression contexts.** `${{ run.trigger }}`
  passed lint and failed at runtime. Verify expressions with an actual run.
- **Duration doesn't indicate a cache hit.** A `cache_hit` task still reports
  `CompletedRuntimeSeconds` (it includes layer assembly). Read
  `Status.FinishedSubStatus`.
- **`CacheKey` is a better probe than hit/miss.** A stable key can still execute
  if nothing populated it yet. To ask "did my edit disturb these inputs?", use
  `assert_same_key` / `assert_diff_key`.
- **`rwx results` exits non-zero on a failed run** but still prints valid JSON.
  Parse stdout before trusting the exit code.
- **SuperDB v0.3.0 recursive-`fn` scoping bug.** `fn descend(t): [t,
  ...[unnest t.Subtasks | unnest descend(this)]]` on `{Key:"root",
  Subtasks:[{Key:"kid"}]}` returns `[kid, kid, kid]` — the parameter is shadowed
  by the inner `this`. `_FLATTEN` uses fixed-depth `fork` instead.
- **The task tree isn't flat.** Packages/parallel tasks nest under `Subtasks`,
  and `~base-image` / `~base-config` appear alongside yours. Use `_FLATTEN`.
- **`rwx run` patches uncommitted edits into the clone.** A dirty tree
  invalidates any cache-key-across-commits experiment — check
  `git status --porcelain` first.
- **`git/clone` strips `.git` by default** (`preserve-git-dir: false`). Don't
  assume the workspace looks like a checkout.
- **"Deterministic" is about output bytes, not the command.** A git clone writes
  a wall-clock timestamp into `.git/logs/HEAD`, churning downstream keys though
  the command is fixed (example 10). Diff what a task *wrote*, not what it ran.

## Conventions

- Definitions: `.rwx/cache-NN-slug.yml`; cases: `test/cases/NN-slug.sh`.
- Task keys read as what they show (`one-positive-makes-it-an-allowlist`, not
  `test3`).
- Keep tasks trivial. These exercise RWX, not workloads.
