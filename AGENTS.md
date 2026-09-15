# AI Development Instructions

This is the mandatory entrypoint for every agent working on `brur-world`.

Before any code change, architecture work, refactor, code review, tracked issue/PR work, build, investigation, or validation:

1. Read this file completely.
2. Read root `ARCHITECTURE.md` completely. `ARCHITECTURE.md` is canonical for architecture.
3. Read root `AGENTS_FULL.md` completely. It contains the full repository workflow contract and is incorporated into this file by reference.
4. Read the current issue/task and acceptance criteria.

If this file and `AGENTS_FULL.md` overlap, both apply. The rules below are intentionally repeated and take precedence over any interpretation that would cause an agent-owned task to stop early.

## NON-NEGOTIABLE: agent-owned work keeps running

**An agent-owned tracked task defaults to `RUNNING`. It stays `RUNNING` until it is genuinely `DONE`, `WAITING_FOR_HUMAN`, or `BLOCKED`.**

The project leader must never need to type `fortsätt`, ask for status, or send another message merely to make an already agent-owned task advance.

The state model is:

```text
RUNNING -> RUNNING -> RUNNING -> ... -> DONE

RUNNING -> WAITING_FOR_HUMAN   only for a concrete genuinely human-only action
RUNNING -> BLOCKED             only when execution is technically impossible with available tools/environment
```

There is deliberately **no** transition such as:

```text
RUNNING -> answered user -> stopped
RUNNING -> status reported -> stopped
RUNNING -> substep finished -> stopped
RUNNING -> commit created -> stopped
RUNNING -> PR created -> stopped
RUNNING -> build finished -> stopped
RUNNING -> test/CI failed -> stopped
RUNNING -> found fixable blocker -> stopped
RUNNING -> explained next step -> stopped
```

Those are intermediate events. After them, the task is still `RUNNING` and the agent must execute the next agent-owned step immediately when tools/environment allow it.

### Mandatory continuation loop

Before ending **every response** while tracked work is active:

1. Re-identify the active tracked task.
2. Ask: is the requested scope actually complete?
3. If not, identify the next concrete action.
4. Ask: is that action agent-owned and executable with the available tools/environment?
5. If yes: **do it now; do not end the response.**
6. Repeat from step 2 until `DONE`, `WAITING_FOR_HUMAN`, or `BLOCKED` is true.

A user-facing answer, explanation, apology, status update, plan, summary, tool result, failed validation, `DO NOT MERGE`, commit, push, PR creation, CI completion, or statement such as "I will continue" is **never** by itself a termination condition.

### Conversational interruptions do not pause work

Messages such as `status?`, `vad händer?`, `varför?`, `följ AGENTS.md`, `fortsätt`, questions about the current work, or corrections inside the current scope are conversational interruptions unless the project leader explicitly pauses, stops, replaces, or changes the task.

Required behavior:

```text
answer/correct
-> re-identify active task
-> execute next agent-owned action
-> keep executing
-> stop only at DONE / WAITING_FOR_HUMAN / BLOCKED
```

Do not answer the interruption and then silently wait.

### Failures mean fix, not handoff

If CI, a test, Safe Check, build, mergeability check, integration check, implementation, or other objective validation fails and the failure is reasonably agent-fixable, the task remains `RUNNING`.

Required behavior:

```text
failure
-> investigate
-> fix
-> revalidate
-> repeat until green or a genuine human-only/technical blocker exists
```

**Red + agent-fixable = keep working.**

### Human check resolution resumes automatic continuation

When the project leader supplies the requested human result, for example `test ok #191`, control immediately returns to the agent. The agent must perform every remaining agent-owned step in the same active turn: synchronize/recheck current state, repair stale metadata, refresh relevant validation, update `BRUR — Needs You` where applicable, merge automatically when repository rules permit and the decision is `MERGE`, and report only after the workflow reaches its terminal state.

### The only valid stopping states

`DONE` means the requested tracked scope is complete, including required agent-owned delivery/cleanup steps.

`WAITING_FOR_HUMAN` is valid only when a specific remaining action genuinely requires the project leader: a product/architecture decision, meaningful subjective/hardware-specific verification, unsafe/destructive approval, credential/permission action, or another action the agent cannot reasonably perform. Persist it in `BRUR — Needs You` where applicable and state exactly what is required.

`BLOCKED` is valid only when execution is technically impossible with the currently available tools/environment and there is no safe agent-owned workaround. State the exact blocker and the smallest required external action. Tool inconvenience, a failed first approach, stale state, ordinary conflicts, missing investigation, or an agent-fixable failure are not `BLOCKED`.

If none of these three terminal states is true, **DO NOT STOP. EXECUTE THE NEXT AGENT-OWNED ACTION.**

## Full workflow contract

All remaining repository workflow, verification, merge safety, parallel-session, Safe Command Link, Needs You, dependency-graph, testing, delivery, and related rules are defined in `AGENTS_FULL.md` and remain mandatory. This entrypoint exists only to make the continuation invariant impossible to miss; it does not weaken or replace any existing rule.
