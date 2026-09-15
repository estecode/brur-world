# AI Development Instructions

You are an expert Godot 4 and systems software developer working on `brur-world`. This repository follows reusable process defaults from `estecode/ai-project-standard`, but this local file is self-contained and is the operative workflow contract. `ARCHITECTURE.md` is canonical for architecture.

## Mandatory first step

Before any code change, architecture work, refactor, or code review:

1. Read this `AGENTS.md`.
2. Read root `ARCHITECTURE.md`.
3. Read the current issue/task and acceptance criteria.

If a requested change conflicts with `ARCHITECTURE.md`, identify the conflict and use the smallest compliant alternative.

## NON-NEGOTIABLE execution invariant

### PRIMARY CONTINUATION RULE — ACTION BEFORE STATE CLASSIFICATION

For an active tracked task, the first continuation question is always:

```text
Is there any concrete agent-owned action that can advance the active task?

YES -> EXECUTE IT NOW.
       Do not describe it to the project leader instead of doing it.
       After the action, ask this same question again.

NO  -> only now evaluate whether the task is DONE, WAITING_FOR_HUMAN, or BLOCKED.
```

This rule is evaluated **before** reasoning about handoff state. Do not start by asking whether the task might be blocked, whether CI exists, whether a later check needs the project leader's Mac, or whether enough progress has been made to report. First exhaust concrete agent-owned work that is executable with the available tools/environment.

### NEVER NARRATE CONTINUATION — EXECUTE IT

While a tracked task is active, if the agent is about to write or has formulated any statement that identifies remaining agent-owned work — for example `next I will...`, `I can still...`, `what remains is...`, `I need to investigate...`, or a list of further executable actions — **do not send that response**. Treat the first such action as the next tool/action call and execute it immediately. Continue executing subsequent agent-owned actions and re-evaluating the primary continuation rule.

A description of executable future work is proof that the task is still executable and therefore proof that a final response is not yet eligible.

```text
WRONG:
discover remaining work A, B, C
-> tell project leader about A, B, C
-> stop

REQUIRED:
discover remaining work A, B, C
-> execute A
-> execute B
-> execute C
-> ask whether another agent-owned action exists
-> continue while the answer is YES
-> only then evaluate terminal state
```

**Self-check:** If deleting the proposed final response would reveal an obvious next tool call or agent-owned action, **make that call instead of sending the response.**

An accepted agent-owned task remains active until the requested scope is actually complete. The only terminal states are:

```text
DONE              requested scope and required agent-owned delivery/cleanup are complete
WAITING_FOR_HUMAN no agent-owned action remains and a specific genuinely human-only action is required now
BLOCKED           no agent-owned action remains and execution is technically impossible with the available tools/environment and no safe workaround exists
```

Everything else remains active. Answering a question, giving status, explaining a failure, completing a substep, creating a branch/commit/PR, finishing a build, receiving CI/test results, finding a recoverable conflict, or identifying an agent-fixable blocker is not a stopping state.

The project leader must never need to type `fortsätt`, ask for status, or send another message merely to advance already agent-owned work. This does not authorize unsafe/destructive actions, bypass required human approval, or imply background execution after the current execution opportunity ends.

## Repository orientation and Repomix fallback

GitHub/current-checkout original files remain the source of truth. A Repomix snapshot, when available, is an optional fast orientation cache only.

- After the mandatory reads, prefer an available Repomix snapshot for fast orientation before opening targeted source files.
- Never treat Repomix as proof that it matches the target revision. Verify relevant original files before changing/reviewing code.
- If Repomix is missing, stale, incomplete, ambiguous, or fails, fall back immediately to GitHub/original files. Do not ask the project leader to regenerate it merely to continue ordinary work.
- Do not build synchronization/RAG/index infrastructure merely to keep Repomix current.

## Issue workflow

For tracked implementation such as `fixa #48`:

1. Read required local files and issue acceptance criteria.
2. Base safely on latest known `main` without overwriting local work.
3. Use `issue/<number>-<short-name>` and isolate concurrent issue work.
4. Implement the smallest architecture-compliant change inside scope.
5. Run all relevant available objective validation. Do not delegate machine-verifiable checks to manual playtesting.
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

`MERGE` means all relevant available objective validation passed and no meaningful manual check remains. `CHECK THEN MERGE` means objective validation passed but one meaningful perceptual, interactive, hardware-specific, production-data/environment-specific, or otherwise non-automatable human check remains. `DO NOT MERGE` means a blocker, failed relevant check, or material unresolved risk remains.

### Verification and merge decision

Correctness is agent-owned where reasonably machine-verifiable. Human verification must not be a shortcut.

Use validation in increasing scope as the implementation stabilizes:

```text
TARGETED VALIDATION
-> INTEGRATION VALIDATION
-> FINAL RELEVANT REGRESSION
-> MERGE DECISION
```

- During implementation run the smallest deterministic/native/headless/real-data check that directly exercises the touched behavior.
- After targeted green, broaden to affected subsystem and real boundaries.
- Run full relevant regression/CI on the stable final candidate, not as the ordinary debugging loop.
- After a failure, repair and rerun the smallest invalidated proof, then broaden again.
- Evidence applies to the revision/integration context actually tested. Revalidate invalidated evidence after code/main changes.
- Efficiency never weakens required merge gates, statuses, local PR checks, integration validation, or relevant regression.
- Objective runtime invariants should be automated where reasonably possible; do not create brittle or disproportionately expensive automation merely because a property is theoretically measurable.

Final delivery reporting includes issue, branch, delivery commit, actual validation/results, PR, issue-update status, outstanding notes, and the same merge decision as the PR.

## Project-leader workflow

GitHub is persistent project state; chat sessions are disposable work surfaces. The project leader must not need to remember which tab created/tested/discussed an issue or PR.

### Active-task continuity across conversational interruptions

A tracked issue, PR, wave, investigation, build or validation remains active across conversational turns until terminal. A project-leader question, correction, status request, explanation request, reminder, or `fortsätt` does not replace or pause it unless the project leader explicitly changes scope or says stop/pause/wait/abandon.

For conversational interruptions:

```text
answer/correct concisely
-> re-identify active task
-> apply PRIMARY CONTINUATION RULE
-> execute instead of narrating continuation
```

Status reporting is observational, not a handoff.

### Human-check resolution continuation

When the project leader resolves a required human check, control returns immediately to the agent. Continue through all remaining agent-owned synchronization, metadata repair, merge-safety refresh/revalidation, Needs You cleanup, merge, and post-merge cleanup. Do not stop between these steps unless the primary continuation rule returns NO and a genuine terminal state exists.

A human-executed Safe Check that reports an objective failure returns ownership to the agent. Diagnose, repair, and exhaust relevant agent-owned validation before requesting another local run. Never use the project leader as an iterative test runner.

### Terminal-state and repeated-action guard

Repository mutations are idempotent from the agent's point of view.

- After a mutation, inspect the returned state or perform at most one targeted read-back if needed.
- Once the intended terminal mutation is confirmed, do not repeat it merely to make sure.
- Never invoke the same successful mutation twice in succession with effectively identical arguments.
- A failed safely retryable mutation permits one corrected retry; before a third equivalent attempt, diagnose instead of looping.
- A successful read-back is sufficient; do not poll a terminal state that cannot become more complete.

### Response termination gate

The termination gate runs **only after the PRIMARY CONTINUATION RULE has returned NO**.

```text
1. Is there any concrete agent-owned action that can advance the task?
   YES -> EXECUTE IT. Return to step 1.
   NO  -> continue.

2. Is requested scope and required cleanup complete?
   YES -> DONE -> final response allowed.
   NO  -> continue.

3. Is a specific human-only action required NOW?
   YES -> WAITING_FOR_HUMAN -> final response allowed with that exact action.
   NO  -> continue.

4. Is execution technically impossible with available tools/environment,
   with no safe agent-owned workaround?
   YES -> BLOCKED -> final response allowed with exact blocker and smallest required user action.
   NO  -> the task remains active; search for the next concrete agent-owned action rather than narrating a stop.
```

A progress report, partial completion summary, validation list, commit/PR update, CI-start/pending notice, explanation of remaining work, or statement that work will continue is never itself terminal.

Failed CI, failed `brur-world/local-pr-check`, red tests, objective Safe Check failures, suspected implementation/check bugs, stale branches, routine merge/rebase work, recoverable conflicts, missing investigation, agent-fixable `DO NOT MERGE` blockers, and pollable pending work all remain agent-owned.

### Continuous Git/PR/CI execution

- Pollable CI/build/test/status pending work remains active. Poll at sane bounded intervals or perform safe same-task work between polls.
- On terminal green, immediately apply the primary continuation rule and perform the next PR/task/merge-safety action.
- On terminal red, diagnose, repair, rerun the smallest relevant validation, and continue.
- Missing hosted CI is not by itself `WAITING_FOR_HUMAN` if other agent-owned analysis, implementation, tests, Git/GitHub work, or verification remains.
- PR finalization and required cleanup are part of the task.
- Investigation must converge on executable actions. Once enough evidence exists for the smallest safe next step, execute it instead of producing more plans/status prose.

## Parallel sessions and isolated work

- Before starting tracked work, check GitHub for an existing active branch/PR/implementation of the same issue.
- Before recommending an issue as available, verify current GitHub implementation state; issue-open alone is insufficient.
- Each concurrent issue uses an isolated branch/worktree/equivalent checkout. Never use the project leader's normal checkout as a shared branch-switching workspace.
- Prefer dependencies through `main`; avoid stacked branch chains by default.
- Parallelize only when resources are safely independent. Technical parallelism is agent responsibility.

## Merge safety under changing main

- A merge recommendation is evidence for the revision/integration context actually validated.
- Immediately before merge, verify current PR head, required statuses/checks, mergeability, and integration relevance against current `main`; perform the smallest relevant refresh/revalidation.
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
- Requests such as `status #102`, `test ok #102`, `merge #102`, or `vad behöver jag göra?` resolve from current GitHub state, not chat memory.

## Safe Command Links

This project supports `estecode/safe-command-links` for human-executable PR checks and current-checkout playtests.

```text
Safe Command Links: supported
Repository: estecode/brur-world
PR check command: pr-check
Parameters: pr:positive-int
Playtest command: playtest
Parameters: target:enum=game,gps,driving
```

For applicable `CHECK THEN MERGE` PRs use:

```text
RUN: [▶ Run safe check](http://127.0.0.1:17384/safecommand/project?repo=estecode/brur-world&command=pr-check&pr=<PR number>)
```

Never put a developer's absolute checkout path in a PR. Safe Command Links maps the repository to the local checkout and validates approved commands/parameters. `brur-world` owns project-specific `pr-check`/`playtest` behavior; Safe Command Links remains generic.

Local `pr-check` objective results are persistent project state on the exact PR head under `brur-world/local-pr-check`: `pending`, `failure`, or `success`. Human perception approval is separate. Missing/pending/failed/stale-head status fails closed when the PR requires this check.

### Manual test handoff

After all relevant available objective validation is complete, if human verification still remains:

- Open PR: provide the exact Safe Command Link when applicable; do not ask the project leader to switch branches manually.
- Merged/current-main work: use supported `playtest` Safe Command Link when applicable.
- State exactly what remains to verify and why it cannot reasonably be automated.
- Never ask for manual verification that deterministic/native/headless/real-data validation should reasonably cover first.
- An objective Safe Check failure returns ownership to the agent until repaired/revalidated.

## Dependency graph execution

Treat the roadmap as a dependency graph, not a mandatory queue. Read dependencies for non-trivial tracked work. `Independent` means no implementation blocker, not priority. `Blocked` means do not complete until dependencies are satisfied. `Integration-sensitive` means work may proceed with explicit awareness of shared contracts/files.

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

1. Read current `AGENTS.md`, `ARCHITECTURE.md`, the wave definition, and candidate child dependencies.
2. Synchronize GitHub state; do not create competing work for occupied children.
3. Build the ready set from the dependency graph.
4. Use one isolated issue branch/PR per tracked child.
5. Use maximum safe parallelism actually supported; do not claim unavailable background workers.
6. Follow complete objective validation, PR decision, and merge-safety contract for each child.
7. After each merge/dependency change recompute ready set and continue automatically.
8. Continue until every child is merged/satisfied or a genuine human/external blocker prevents further progress.
9. If blocked, persist exact human action in `Needs You` when applicable and continue other independent ready work before stopping.
10. Report `Wave <X> COMPLETE` only when the canonical wave definition is actually satisfied on current `main`.

This command orchestrates existing issue/PR workflow and must not introduce a new dashboard, scheduler, database, branch hierarchy, or orchestration framework merely to make the phrase work.
