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
memory — recalled RWX syntax has been wrong here, and `rwx lint` only checks
syntax (example 09: a bad expression context lints clean and fails at runtime).
`rwx docs pull /migrating/rwx-reference` is the full reference; `rwx docs search
"<query>"` finds specific pages.

## Tooling

- **SuperDB (`super`), not `jq`**, for JSON. The MCP server (`mcp__superdb__*`)
  serves version-matched docs — call `super_help expert` before non-trivial
  SuperSQL. It's neither jq nor quite SQL; the old Zed/zq syntax is incompatible.
- `rwx` CLI must be signed in (`rwx whoami`).

## Adding an example

1. Write `.rwx/<topic>-NN-slug.yml`, one behavior per definition, with a header
   comment stating what it demonstrates and how.
2. Prefer **self-verifying tasks** — `test` inside the `run` script, so the task
   fails the run when the behavior differs (see `cache-04-filter-semantics.yml`).
3. Use **cross-run assertions** for cache keys or hits, which aren't observable
   from inside a task (see `cache-05-downstream-hit-on-miss.yml`). To ask "did
   my edit disturb a task's inputs?", compare `CacheKey` across two runs
   (`assert_same_key` / `assert_diff_key`) — not hit/miss, since a task with a
   stable key still executes the first time nothing has populated it.
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
assert_runtime_positive <label> <task>
assert_lint_clean <config>
assert_log_contains / assert_log_missing <run-id> <task> <substring>
assert_task_message_contains <label> <task> <substring>
finish                                       # prints tally, exits nonzero on failure
```

Run JSON persists in `.results/` (gitignored) — re-query instead of re-running:
`source test/lib/rwx.sh && task_summary <label>`. `task_summary` applies
`_FLATTEN`; a bare `unnest Tasks` query sees only top-level tasks.

## Conventions

- Definitions: `.rwx/<topic>-NN-slug.yml` (`cache-`, `lint-`, …); cases:
  `test/cases/NN-slug.sh`. The number ties a case to its definition; the topic
  is just a hint.
- Task keys read as what they show (`one-positive-makes-it-an-allowlist`, not
  `test3`).
- Keep tasks trivial. These exercise RWX, not workloads.

## Possible next steps

- **Scheduled drift-check via GitHub Actions (TODO).** The examples only regress
  if RWX itself changes behavior — lint starts resolving contexts, cache
  semantics shift, `git/clone` changes its `.git` default. A scheduled GH Actions
  cron running `test/run.sh` on GH's runner, with an `RWX_ACCESS_TOKEN` repo
  secret, would catch that unattended — no RWX-in-RWX, no vault. Not set up; for
  now, run `test/run.sh` locally before tagging a release.
