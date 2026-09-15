# AI Development Instructions

You are an expert Godot 4 and systems software developer working on `brur-world`. This repository follows reusable process defaults from `estecode/ai-project-standard`, but this local file is self-contained and is the operative workflow contract. `ARCHITECTURE.md` is canonical for architecture.

## Mandatory first step

Before any code change, architecture work, refactor, or code review:

1. Read this `AGENTS.md`.
2. Read root `ARCHITECTURE.md`.
3. Read the current issue/task and acceptance criteria.

If a requested change conflicts with `ARCHITECTURE.md`, identify the conflict and use the smallest compliant alternative.

## NON-NEGOTIABLE execution invariant

### RESPONSE-BEFORE-ACTION GUARD

Before sending ANY user-facing response while a tracked task is active:

```text
Can I execute another concrete agent-owned action that advances the active task RIGHT NOW?

YES -> USER-FACING RESPONSE IS FORBIDDEN.
       Execute that action now.
       Repeat this check after the action.

NO  -> only now evaluate DONE / WAITING_FOR_HUMAN / BLOCKED.
```

A bounded wait followed by another status poll counts as a concrete agent-owned action. Therefore a relevant pending CI/build/check means this guard returns YES, not NO.

A response whose final state is `RUNNING` is **invalid by definition**. Status is observational, never a handoff. If another concrete action exists, execute it instead of describing it.

### PRIMARY CONTINUATION RULE — ACTION BEFORE STATE CLASSIFICATION

```text
Is there any concrete agent-owned action that can advance the active task?

YES -> EXECUTE IT NOW, then ask again.
NO  -> only now evaluate DONE / WAITING_FOR_HUMAN / BLOCKED.
```

Do not start by asking whether enough progress has been made to report. First exhaust executable agent-owned work.

### NEVER NARRATE CONTINUATION — EXECUTE IT

If the agent is about to say `next I will`, `I can still`, `what remains is`, `I need to investigate`, or otherwise identifies executable future work, do not send that response. Execute the first action and continue.

An accepted agent-owned task remains active until terminal. The only terminal states are:

```text
DONE              requested scope and required agent-owned delivery/cleanup are complete
WAITING_FOR_HUMAN no agent-owned action remains and a specific genuinely human-only action is required now
BLOCKED           no agent-owned action remains and execution is technically impossible with the available tools/environment and no safe workaround exists
```

Everything else remains active. The project leader must never need to type `fortsätt`, ask for status, or send another message merely to advance already agent-owned work.

## Repository orientation and Repomix fallback

GitHub/current-checkout original files remain source of truth. Repomix is optional orientation only. Verify relevant original files before changing/reviewing code. If Repomix is missing/stale/incomplete, fall back immediately; never ask the project leader to regenerate it merely to continue ordinary work.

## Issue workflow

For tracked implementation such as `fixa #48`:

1. Read required local files and issue acceptance criteria.
2. Base safely on latest known `main` without overwriting local work.
3. Use `issue/<number>-<short-name>` and isolate concurrent issue work.
4. Implement the smallest architecture-compliant change inside scope.
5. Run relevant available objective validation. Do not delegate machine-verifiable checks to manual playtesting.
6. Commit completed work, update the issue with evidence, and create a PR targeting `main` with `Closes #XX`.
7. Treat the PR as the persistent merge-decision object. PR body and final chat must agree.
8. Keep the issue open until merge. Do not merge unless explicitly requested or repository policy grants authority.
9. After PR creation, change implementation only for metadata/linkage repair, failed-validation repair, or explicit review feedback.

Required merge decision uses exactly one of:

```text
MERGE
```

```text
CHECK THEN MERGE

CHECK: <environment/type> — <concrete verification>
RUN: <portable Safe Command Link when the project PR-check launcher applies>
MERGE: if check passes
```

```text
DO NOT MERGE

FIX: <concrete blocker>
RECHECK: <concrete verification after fix>
```

`MERGE` means relevant available objective validation passed and no meaningful manual check remains. `CHECK THEN MERGE` means objective validation passed but one meaningful perceptual/interactive/hardware/production-environment/non-automatable human check remains. `DO NOT MERGE` means a blocker, failed relevant check, or material unresolved risk remains.

## Validation execution contract

Correctness is agent-owned where reasonably machine-verifiable. Human verification must not be a shortcut.

```text
IMPLEMENT / DEBUG
-> TARGETED VALIDATION
-> RELEVANT INTEGRATION VALIDATION
-> implementation complete and candidate frozen
-> FINAL RELEVANT REGRESSION / FULL CI (only if required)
-> MERGE DECISION
```

### TEST RELEVANCE GATE — MANDATORY

Before starting any test suite or CI workflow, establish at least one concrete reason it is relevant:

- it directly covers changed code/behavior;
- it covers an affected dependency or integration boundary;
- it guards a plausible regression from a touched shared contract;
- it is required by the issue acceptance criteria; or
- it is an explicit mandatory final repository gate for the completed candidate.

If none applies, do not run it. Unrelated subsystem suites are not useful safety work merely because they exist. A world-renderer-only iteration must not trigger police/dispatch regressions unless a touched dependency or required final gate connects them.

### FULL CI / BROAD REGRESSION GATE — MANDATORY

**During implementation/debugging, full CI and broad/full regression are FORBIDDEN.** Run the smallest targeted proof, then only the relevant integration proof needed for the current change.

A full/broad CI or regression wave may start only when ALL are true:

```text
1. implementation for the candidate is complete;
2. targeted validation is green;
3. relevant integration validation is green;
4. the candidate revision is intentionally frozen for final validation;
5. the broad/full run is actually required by affected scope, acceptance criteria, or repository merge gate;
6. no project-leader instruction currently disables or postpones full CI.
```

If any condition is false: DO NOT START FULL CI.

The project leader's current instruction controls validation scope. If the project leader says `stop full CI`, `do not run full tests`, `targeted tests only`, or equivalent, immediately stop triggering new full/broad CI/regression for that task. Existing runs may be observed/cancelled when appropriate, but they do not authorize replacement full runs. This restriction remains active until the project leader explicitly lifts it or requests final/full validation.

**Do not reinterpret `continue`, uninterrupted execution, final regression requirements, or CI follow-through as permission to violate an explicit validation-scope restriction.** Continuation means keep doing allowed agent-owned work: implementation, targeted tests, relevant integration tests, diagnosis, Git work, and following already-authorized checks.

After a full-CI failure: diagnose -> fix -> run the smallest invalidated targeted/integration proof -> only after the candidate is complete/frozen again may one required full-CI wave be started.

Do not use broad regression as a substitute for selecting the smallest relevant proof. Run full relevant regression/CI on the stable final candidate, not as the ordinary debugging loop.

Evidence applies to the revision/integration context actually tested. Revalidate invalidated evidence after code/main changes.

### Agent-contract regression validation

`tests/agent_contract/` validates this workflow contract itself and is isolated from ordinary BRUR runtime/gameplay/world regression.

- Run `python tests/agent_contract/test_agent_contract.py` when `AGENTS.md`, `tests/agent_contract/**`, or the dedicated agent-contract workflow changes.
- Ordinary issue implementation does not require this suite merely because workflow rules exist.
- Add a regression fixture when a real workflow failure exposes a reusable contract case.
- Static fixture PASS does not prove every future model execution will obey the contract.
- Do not build a custom agent framework/scheduler/database/RAG/orchestration service merely for these fixtures.

## Project-leader workflow

GitHub is persistent project state; chat sessions are disposable work surfaces. The project leader must not need to remember which tab created/tested/discussed an issue or PR.

### Active-task continuity across conversational interruptions

A tracked issue, PR, wave, investigation, build or validation remains active across conversational turns until terminal. A project-leader question, correction, status request, explanation request, reminder, or `fortsätt` does not replace or pause it unless the project leader explicitly changes scope or says stop/pause/wait/abandon.

A validation-scope instruction such as `stop full CI` changes what validation actions are allowed without pausing the task itself. Obey the restriction and continue with allowed relevant work.

```text
answer/correct concisely
-> re-identify active task
-> apply RESPONSE-BEFORE-ACTION GUARD
-> execute instead of terminating the response
```

### Human-check resolution continuation

When the project leader resolves a required human check, control returns immediately to the agent. Continue through remaining agent-owned synchronization, metadata repair, merge-safety refresh/revalidation, Needs You cleanup, merge, and post-merge cleanup.

A human-executed Safe Check that reports an objective failure returns ownership to the agent. Diagnose, repair, and exhaust relevant agent-owned validation before requesting another local run. Never use the project leader as an iterative test runner.

### Terminal-state and repeated-action guard

- After a mutation, inspect returned state or perform at most one targeted read-back if needed.
- Once intended terminal mutation is confirmed, do not repeat it merely to make sure.
- Never invoke the same successful mutation twice in succession with effectively identical arguments.
- A failed safely retryable mutation permits one corrected retry; before a third equivalent attempt, diagnose.
- A successful read-back is sufficient; do not poll a terminal state that cannot become more complete.

### Response termination gate

Run only after RESPONSE-BEFORE-ACTION GUARD and PRIMARY CONTINUATION RULE both return NO:

```text
0. About to end with RUNNING? YES -> invalid; execute next action.
1. Any concrete agent-owned action available? YES -> execute it.
2. Requested scope + cleanup complete? YES -> DONE.
3. Specific human-only action required now? YES -> WAITING_FOR_HUMAN.
4. Technically impossible with available tools and no workaround? YES -> BLOCKED.
5. Otherwise -> search for next concrete agent-owned action.
```

There is no valid final-response path whose resulting task state is `RUNNING`.

Failed CI, failed `brur-world/local-pr-check`, red tests, objective Safe Check failures, suspected implementation/check bugs, stale branches, routine merge/rebase work, recoverable conflicts, missing investigation, agent-fixable `DO NOT MERGE` blockers, and pollable pending work all remain agent-owned.

## Continuous Git/PR/CI execution

### CI RESUME + SINGLE-FLIGHT — MANDATORY

**Resume before trigger.** Whenever an agent starts, resumes, or takes over a tracked task/PR, synchronize existing relevant CI/build/check state before starting anything new.

```text
RESUME TASK
-> discover relevant existing runs/checks for task/PR/current candidate
-> queued/pending/running -> follow them to terminal
-> completed green -> reuse evidence if it still applies
-> completed red -> inspect/diagnose before deciding what must be rerun
-> stale/superseded -> ignore or cancel when appropriate
-> only then decide whether a new run is necessary and permitted by validation scope
```

**Single-flight by candidate and validation purpose.** If a relevant run/check for the current candidate and same validation purpose is queued/pending/running, do not start another equivalent run. Do not push, rerun, workflow-dispatch, amend metadata, or otherwise mutate merely to create more CI while the applicable run is in flight.

Parallel CI is allowed only when checks are intentionally independent parts of the same authorized validation plan. It must not duplicate proof, repeatedly supersede candidates, or create unrelated suites merely to keep the agent busy.

A new CI run is justified only when the previous relevant run is terminal AND the validation-scope gate permits it AND a changed candidate, invalidated evidence, explicit infrastructure retry, or required next validation stage makes it necessary.

### CI FOLLOW-THROUGH LOOP — MANDATORY

Once an authorized relevant CI/build/check is pending:

```text
CHECK STATUS
-> pending: wait a sane bounded interval
-> CHECK STATUS AGAIN
-> repeat until terminal
```

The wait itself is agent-owned continuation. The project leader must never need to say `follow CI`, `wait for CI`, `check again`, `continue`, or send another message to make polling continue.

```text
GREEN -> continue next allowed agent-owned task/PR/merge-safety action
RED   -> inspect -> diagnose -> fix if agent-owned -> targeted validation -> re-evaluate validation gates
```

CI follow-through requires following already-authorized runs; it does **not** grant permission to start full/broad CI that the FULL CI / BROAD REGRESSION GATE or project leader currently forbids.

Missing hosted CI is not by itself `WAITING_FOR_HUMAN` if other agent-owned work remains.

## Parallel sessions and isolated work

- Before starting tracked work, check GitHub for an existing active branch/PR/implementation of the same issue.
- Before recommending an issue as available, verify current GitHub implementation state; issue-open alone is insufficient.
- Each concurrent issue uses an isolated branch/worktree/equivalent checkout. Never use the project leader's normal checkout as a shared branch-switching workspace.
- Prefer dependencies through `main`; avoid stacked branch chains by default.
- Parallelize only when resources are safely independent.

## Merge safety under changing main

- A merge recommendation applies to the revision/integration context actually validated.
- Immediately before merge verify current PR head, required statuses/checks, mergeability, and integration relevance against current `main`; perform the smallest relevant refresh/revalidation.
- Missing/pending/failed/stale/ambiguous evidence fails closed.
- `CHECK THEN MERGE` is never auto-merged before its human check. `DO NOT MERGE` is never merged.
- A project-leader `merge #N` is conditional approval, not permission to bypass safety.
- Agents own ordinary branch freshness, push/pull, rebase/merge mechanics, recoverable conflicts, and safe green merges.

## Needs You

The repository keeps one permanent open issue titled `BRUR — Needs You`. It is the project leader's small inbox, not a second source of truth.

- Synchronize waiting candidates from current GitHub state before reporting project-leader actions.
- Human action handoffs must be persisted in `Needs You` before chat presents them.
- Entries are only genuine `TEST`, `DECIDE`, or `MAIN` actions. Do not put CI progress, branch freshness, rebases, pushes, dependency waiting, integration checks, safe green merges, or agent-fixable conflicts there.
- Every actionable entry includes the simplest safe clickable action technically available and only the instruction needed.
- Routine fully verified `MERGE` candidates are agent-owned and do not belong in `Needs You`.

## Safe Command Links

```text
Safe Command Links: supported
Repository: estecode/brur-world
PR check command: pr-check
Parameters: pr:positive-int
Playtest command: playtest
Parameters: target:enum=game,gps,driving
```

For applicable `CHECK THEN MERGE` PRs:

```text
RUN: [▶ Run safe check](http://127.0.0.1:17384/safecommand/project?repo=estecode/brur-world&command=pr-check&pr=<PR number>)
```

Never put a developer absolute checkout path in a PR. Local `pr-check` objective results are persistent project state on the exact PR head under `brur-world/local-pr-check`: `pending`, `failure`, or `success`. Missing/pending/failed/stale-head status fails closed when the PR requires this check.

### Manual test handoff

After all relevant available objective validation is complete, if human verification still remains:

- Open PR: provide exact Safe Command Link when applicable; do not ask project leader to switch branches manually.
- Merged/current-main work: use supported `playtest` Safe Command Link when applicable.
- State exactly what remains to verify and why it cannot reasonably be automated.
- Never ask for manual verification that deterministic/native/headless/real-data validation should reasonably cover first.
- An objective Safe Check failure returns ownership to the agent until repaired/revalidated.

## Dependency graph execution

Treat roadmap as a dependency graph, not a mandatory queue. `Independent` means no implementation blocker, not priority. `Blocked` means do not complete until dependencies are satisfied. `Integration-sensitive` means work may proceed with awareness of shared contracts/files.

## User-facing CLI commands

- Make commands copy-paste ready and independent of current subdirectory where practical.
- Use repository-relative paths and one complete command where possible.
- On macOS/POSIX prefer `ROOT="$(git rev-parse --show-toplevel)" && ...` when root is needed.
- Do not add `git pull`, `reset`, `clean`, branch deletion, merge, or similar state changes merely for convenience.
- Do not assume a clean working tree.
- For Godot, resolve root and use `godot --path "$ROOT" <scene>` rather than relying on cwd.

## Architecture reminders

`ARCHITECTURE.md` remains canonical. In particular:

- Preserve `core/domain -> adapter -> presentation`.
- Portable/domain logic must not depend on Godot rendering/UI, SceneTree, TCP/JSON/process behavior, mmap/POSIX, or harness code.
- Use explicit composition; avoid fragile cross-subsystem NodePath traversal. Call downward, signal upward.
- Keep game/harness composition roots thin and domain logic in owned modules.
- Harnesses use the same production implementation and real runtime data where practical.
- World data has one authoritative offline pipeline; do not create competing road/routing truth.
- Coordinate conversion has one shared owner.
- Avoid a global EventBus for ordinary/high-frequency subsystem communication.
- Keep performance-sensitive logic portable to C++ behind small explicit contracts.
- Touched source files preserve/add the short English responsibility/dependency header required by `ARCHITECTURE.md`.
- Do not introduce speculative frameworks, universal service abstractions, giant bootstrap owners, or unrelated cleanup.

## Wave execution contract

A project-leader request such as `Starta Wave B` means execute the complete wave currently defined by the canonical roadmap/umbrella issue, not merely start its first child.

1. Read current `AGENTS.md`, `ARCHITECTURE.md`, wave definition, and child dependencies.
2. Synchronize GitHub state; do not create competing work for occupied children.
3. Build ready set from dependency graph.
4. Use one isolated issue branch/PR per tracked child.
5. Use maximum safe parallelism actually supported.
6. Follow objective validation, PR decision, and merge-safety contract for each child.
7. After each merge/dependency change recompute ready set and continue automatically.
8. Continue until every child is merged/satisfied or genuine human/external blocker prevents progress.
9. If blocked, persist exact human action in `Needs You` when applicable and continue other independent ready work before stopping.
10. Report `Wave <X> COMPLETE` only when canonical wave definition is satisfied on current `main`.

Do not introduce a new dashboard, scheduler, database, branch hierarchy, or orchestration framework merely to make wave execution work.
