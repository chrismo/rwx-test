# Working in this repo

This repo exists because model intuition about RWX caching is unreliable in
ways that are expensive to discover. Every claim here is backed by an actual
run. That is the whole product — protect it.

## The one rule

**Never mark a claim confirmed without a run that confirmed it.**

Not "the docs say so." Not "this should cache." A claim is confirmed when
`rwx run` produced results JSON showing it, and a case in `test/cases/` asserts
it. Everything else is `pending` in the README status table, stated as a
prediction.

If you find yourself reasoning about what RWX *would* do — stop and run it.
That reflex is the entire point of the repo.

## Spend discipline (public repo)

This repo is public. An outsider must not be able to make it spend.

- **Never add a `pull_request` trigger.** Not to any definition, for any
  reason. Opening PRs must start nothing.
- **New definitions get `on: cli:` and nothing else** unless the claim under
  test is specifically about a different trigger.
- **Adding any self-starting trigger needs explicit human approval**, and must
  be guarded (`if: ${{ event.git.branch == 'main' }}`) and kept trivial.
- Today exactly one definition can start itself:
  `.rwx/cache-03-cli-vs-push-cache.yml`. **Pushing to main fires it.** Mention
  that when you propose a push.

## Before answering anything about RWX

Load the `rwx` skill and `rwx docs pull` the relevant page. Do not answer from
memory — recalled RWX syntax has been wrong here more than once, and `rwx lint`
does **not** catch every error (see traps below).

`rwx docs pull /migrating/rwx-reference` is the full reference with a table of
contents; `rwx docs search "<query>"` finds specific pages.

## Tooling

- **SuperDB (`super`), not `jq`**, for all JSON querying. The MCP server
  (`mcp__superdb__*`) serves version-matched docs — call `super_help expert`
  before writing non-trivial SuperSQL. It is neither jq nor quite SQL, and the
  old Zed/zq syntax found in search results is incompatible.
- `rwx` CLI must be signed in (`rwx whoami`).

## Adding a test

1. Write `.rwx/cache-NN-slug.yml`. Open it with a comment block stating the
   claim under test and the method. One claim per definition.
2. Prefer **self-verifying tasks** — assert with `test` inside the `run`
   script so the task fails the run when the claim doesn't hold. A single run
   is then a complete test (see `cache-05-filter-semantics.yml`).
3. Use **cross-run assertions** when the claim is about cache keys or hits,
   since those aren't observable from inside a task (see
   `cache-06-downstream-hit-on-miss.yml`).
4. Vary inputs with `--init` salts rather than editing files between runs —
   repeatable, and leaves no working-tree mess.
5. Write `test/cases/NN-slug.sh` sourcing `test/lib/rwx.sh`.
   `test/run.sh NN` matches on the numeric prefix.
6. `rwx lint .rwx/` then run it. Update the README status table **only after**
   it passes.

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

Results JSON persists in `.results/` (gitignored). Re-query a finished run
instead of paying to re-run it. For ad-hoc digging, source the library and use
`task_summary` — it applies `_FLATTEN`, so it won't miss nested tasks:

```sh
source test/lib/rwx.sh && task_summary noise-b
```

A bare `super -c 'unnest Tasks | …' .results/noise-b.json` also works, but only
sees top-level tasks. Fine for a quick look, wrong for an assertion.

## Traps that have already bitten

- **`rwx lint` does not validate expression contexts.** It passed
  `${{ run.trigger }}`, which is not a real context and would have failed at
  runtime. Verify expressions against the docs, then with an actual run.
- **Duration does not indicate a cache hit.** A confirmed `cache_hit` task
  reported `CompletedRuntimeSeconds: 9` — that clock includes layer assembly.
  Read `Status.FinishedSubStatus`.
- **`CacheKey` is a better probe than hit/miss.** A task can have a stable key
  and still execute because nothing had populated it yet. A missing hit is not
  proof of a busted key. To ask "did my edit disturb these inputs?", use
  `assert_same_key` / `assert_diff_key`.
- **`rwx results` exits non-zero when the run failed** but still prints valid
  JSON on stdout. Parse stdout before trusting the exit code.
- **SuperDB v0.3.0 recursive `fn` scoping bug.** The parameter is shadowed by
  an inner subquery's `this`:
  `fn descend(t): [t, ...[unnest t.Subtasks | unnest descend(this)]]` applied
  to `{Key:"root", Subtasks:[{Key:"kid"}]}` returns `[kid, kid, kid]` — parent
  dropped, children duplicated. Splitting into two functions does not help.
  `_FLATTEN` in `test/lib/rwx.sh` uses fixed-depth `fork` instead.
- **The task tree is not flat.** Packages and parallel tasks nest under
  `Subtasks`, and RWX's own `~base-image` / `~base-config` tasks appear
  alongside yours. Use `_FLATTEN`, not `unnest Tasks`.

## Conventions

- Definitions: `.rwx/cache-NN-slug.yml`; cases: `test/cases/NN-slug.sh`.
- Task keys read as the assertion they make
  (`one-positive-makes-it-an-allowlist`, not `test3`).
- Comment headers state the claim, the method, and — when the claim came from
  a real incident — what it cost, so the test's purpose survives.
- Keep tasks trivial. These test RWX, not workloads. Cheap tests get run.
