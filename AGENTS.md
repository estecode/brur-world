# AI Development Instructions

You are an expert Godot 4 and systems software developer working on `brur-world`. This repository follows reusable process defaults from `estecode/ai-project-standard`, but this local file is self-contained and is the operative workflow contract. `ARCHITECTURE.md` is canonical for architecture.

## Mandatory first step

Before any code change, architecture work, refactor, or code review:

1. Read this `AGENTS.md`.
2. Read root `ARCHITECTURE.md`.
3. Read the current issue/task and acceptance criteria.

If a requested change conflicts with `ARCHITECTURE.md`, identify the conflict and use the smallest compliant alternative.

## Issue workflow

For tracked implementation such as `fixa #48`:

1. Read the required local files and issue before changing code.
2. Base work safely on the latest known `main` without overwriting local work.
3. Use `issue/<number>-<short-name>` and isolate concurrent issue work.
4. Implement the smallest architecture-compliant change inside issue scope.
5. Run all relevant available objective validation for the touched scope, including deterministic/core, native/headless Godot, and real-data integration checks where applicable. Do not delegate machine-verifiable checks to manual playtesting when they can reasonably be executed by the agent. Never claim validation not performed.
6. Commit the completed work, update the issue with implementation/validation evidence, and create a PR targeting `main` with `Closes #XX`.
7. Treat the PR as the persistent merge-decision object. PR body and final chat must agree.
8. Keep the issue open until merge. Do not merge unless explicitly requested or repository policy grants authority.
9. After PR creation, change implementation only for metadata/linkage repair, failed-validation repair, or explicit review feedback.

Required decision block:

```markdown
## Merge decision

**What changed**
<plain-language summary>

**Why this approach**
<why this was the smallest/correct solution>

**Behavioral impact**
<what can change or regress>

**Executed validation**
<exact checks actually run + results>

**Risk assessment**
<remaining risks, untested areas, known gaps>

**Merge recommendation**
<one decision form below>
```

Use exactly one:

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

Do not use `CHECK THEN MERGE` merely because this is Godot. Do not delegate a check the agent can execute. Manual verification should primarily evaluate perception/feel or behavior that cannot reasonably be automated. Repeated objective manual checks are candidates for automation. Name the concrete scene/harness/runtime verification.

### Verification and the merge decision

You must take responsibility for proving the objective correctness of your changes. Human verification must never be used as a shortcut for something you can reasonably prove yourself.

- `CHECK THEN MERGE` is not justified by the fact that a check requires Godot, scene execution, rendering state, spatial state, interaction state, or real runtime data. If the remaining property is objectively verifiable and can reasonably be asserted by the agent, that verification must be executed before handover.
- If an invariant can reasonably be asserted in headless Godot, write and execute that verification before requesting a human playtest. Examples include viewport bounds, camera/terrain clearance, target-tracking tolerances, object placement against the expected drivable surface, visibility/existence, and state transitions such as manual takeover, GPS control and reroute requests.
- If a bug can be described as a broken objective rule, translate that rule into the smallest stable deterministic assertion rather than asking a human to look for it.
- Do not create brittle or disproportionately expensive automation merely because a property is theoretically measurable. `ARCHITECTURE.md`'s "where reasonably possible" rule still applies.

Final delivery reporting must include issue, branch, delivery commit, actual validation/results, PR, issue-update status, outstanding notes, and the same merge decision as the PR.

## Project-leader workflow

GitHub is the persistent source of truth for project state. Chat sessions are disposable work surfaces: the project leader must not need to remember which ChatGPT tab created, tested, or discussed an issue or PR.

The workflow must remain resumable and fail closed. The project leader may forget, delay, repeat, or miss a handoff without risking correctness, local work, or merge safety. Missing or ambiguous approval means wait; never infer that a test passed or that a merge was approved.

### Parallel sessions and isolated work

Multiple agents or ChatGPT tabs may work on different issues concurrently.

- Before starting tracked work, check GitHub for an existing active branch/PR or other clear implementation of the same issue. Do not accidentally create competing implementations for one issue.
- Each concurrent issue uses its own isolated branch/worktree or equivalent isolated checkout. Never use the project leader's normal checkout as a shared branch-switching workspace for concurrent agent work.
- Prefer dependencies to flow through `main`: merge the dependency, then refresh/revalidate the dependent PR. Do not create stacked branch chains by default.
- Development and objective validation may run in parallel when their resources are independent. Interactive Godot checks that share local runtime resources should normally run one at a time unless safe isolation is explicitly known.
- Technical parallelism is the agents' coordination responsibility, not the project leader's.

### Merge safety under changing main

A prior merge recommendation is evidence about the revision and integration context that was actually validated; it is not permanent permission to ignore later changes to `main`.

- When `main` changes, the agent handling a waiting PR must decide whether that change is relevant to the PR's previous verification. Do not blindly rerun unrelated checks, but do not keep a stale decision when integration-sensitive assumptions changed.
- Immediately before merge, verify the PR against current repository state and perform the smallest relevant refresh/revalidation needed. Merge integration must be serialized so two concurrent sessions cannot both rely on the same stale view of `main`.
- A project-leader command such as `merge #111` is conditional approval: merge that candidate only if it still satisfies repository merge requirements. If relevant changes require a new human check, stop and provide the new exact PR check instead of merging on stale approval.
- Agents should resolve ordinary branch freshness, push/pull, rebase/merge mechanics, and recoverable integration conflicts themselves when safe and within scope. Ask the project leader only when a real product decision, meaningful human verification, or unsafe/destructive choice remains.

### Needs You

The repository keeps one permanent open issue titled `BRUR — Needs You`. It is the project leader's small inbox, not a second source of truth. Its entries summarize the current underlying issues/PRs and link back to them.

Agents must keep `BRUR — Needs You` useful whenever their work creates or resolves a project-leader action:

- `TEST` — a meaningful human check is required; include the exact PR and Safe Command Link when available.
- `READY` — the candidate is ready for explicit merge approval.
- `DECIDE` — a genuine product/architecture decision blocks safe progress.
- `MAIN` — only when there is a concrete reason for the project leader to run the latest integrated game.

Do not put agent-owned work in `Needs You`: CI progress, branch freshness, routine rebases, pushes, dependency waiting, integration checks, or conflicts the agent can safely resolve. If no project-leader action remains in a category, remove that entry. Never treat the inbox itself as proof that a test passed; the relevant PR remains the persistent verification/merge-decision record.

From any chat/session, requests such as `status #102`, `test ok #102`, `merge #102`, or `vad behöver jag göra?` must be resolved from current GitHub state rather than relying on that chat's memory. A bare `test ok` may be accepted only when exactly one active test candidate is unambiguous in context; otherwise ask for the PR number.

This workflow is intentionally implemented with existing GitHub issues/PRs and Safe Command Links rather than a new dashboard, database, or orchestration service. Generalizing it beyond `brur-world` is future work and must not complicate the current repository workflow.

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

`playtest` targets are limited to real supported targets. Add new values only when the corresponding game/harness actually exists; do not create speculative harnesses to populate the allowlist.

When a PR is `CHECK THEN MERGE` and its remaining check can be launched by the project-owned PR-check command, the PR must include a normal clickable localhost HTTP link:

```text
RUN: [▶ Run safe check](http://127.0.0.1:17384/safecommand/project?repo=estecode/brur-world&command=pr-check&pr=<PR number>)
```

GitHub does not reliably make the custom `safecommand://` scheme clickable, so PRs must use the localhost HTTP form above. Safe Command Links listens only on loopback and forwards the request through the same local repository mapping, signed command approval and parameter validation.

Never put a developer's absolute checkout path in a PR. Safe Command Links maps `estecode/brur-world` to the local checkout on each Mac, then verifies the locally signed command approval and validated parameters.

`brur-world` owns what `pr-check` and `playtest` actually do. `pr-check` selects the exact PR revision, prepares isolated runtime state, launches the relevant Godot check, reuses required local runtime data safely, and cleans temporary state after Godot exits. `playtest` prepares the required dependencies for an allowlisted target and launches the current mapped checkout. Safe Command Links must remain generic and must not contain Godot/world-data/project-specific behavior.

If the local Safe Command installation/mapping/approval is missing, the link may fail locally; agents must not infer installation state from GitHub. Repository support is declared here, while local availability is machine state.

### Manual test handoff

After all relevant available objective validation has been completed, if human verification is still required, the agent must make the test handoff explicit and copy-paste ready. The user must never have to infer which checkout or revision should be tested.

- **Open PR:** provide the complete Safe Command Link for that exact PR when `pr-check` applies. Do not ask the user to manually switch the normal checkout to the PR branch.
- **Merged work:** before asking the user to test the merged result in Godot, provide the complete command `git switch main && git pull --ff-only origin main` so the local checkout cannot silently remain on an old `main`.
- Clearly state exactly what remains for the user to verify and why that property could not reasonably be verified automatically.
- Never ask the user to manually verify something that should reasonably have been covered by deterministic, native, headless Godot, or real-data validation first.
- After a merge, if further playtesting or verification is expected, always include the `main` update command even if it was shown earlier in the conversation.

## Dependency graph execution

Treat the roadmap as a dependency graph, not a mandatory queue. Read issue dependencies for non-trivial tracked work. `Independent` means no implementation blocker, not priority. `Blocked` means do not complete until dependencies are satisfied. `Integration-sensitive` means work may proceed with explicit awareness of shared contracts/files. Claim parallel safety only after assessment.

## User-facing CLI commands

- Make commands copy-paste ready and independent of the current repository subdirectory where practical.
- Use explicit repository-relative paths.
- On macOS/POSIX prefer `ROOT="$(git rev-parse --show-toplevel)" && ...` when root is needed.
- Do not add `git pull`, `reset`, `clean`, branch deletion, merge, or similar state-changing operations merely for convenience.
- Do not assume a clean working tree.
- Prefer one complete command.
- For Godot, resolve the root and use `godot --path "$ROOT" <scene>` rather than relying on cwd.

## Architecture reminders

The full architecture contract is in `ARCHITECTURE.md`; it remains canonical. In particular:

- Preserve `core/domain -> adapter -> presentation`.
- Portable/domain logic must not depend on Godot rendering/UI, SceneTree, TCP/JSON/process behavior, mmap/POSIX, or harness code.
- Use explicit composition; avoid fragile cross-subsystem NodePath traversal. Call downward, signal upward.
- Keep game/harness composition roots thin and domain logic in owned modules.
- Harnesses use the same production implementation and real runtime data where practical; do not create duplicate harness implementations.
- World data has one authoritative offline pipeline; do not create competing road/routing truth.
- Coordinate conversion has one shared owner.
- Avoid a global EventBus for ordinary/high-frequency subsystem communication.
- Keep performance-sensitive logic portable to C++ behind small explicit contracts.
- Touched source files preserve/add the short English responsibility/dependency header required by `ARCHITECTURE.md`.
- Do not introduce speculative frameworks, universal service abstractions, giant bootstrap owners, or unrelated cleanup.

When reviewing code, actively flag violations of these rules.
