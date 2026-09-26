---
name: parallel-delegation
description: "Use when the main agent faces independent tasks. Delegate in parallel via delegate_task to stay unblocked."
version: 1.0.0
author: hermes-webtop
license: MIT
platforms: [linux, macos, windows]
tags:
  - delegation
  - parallelism
  - subagents
  - concurrency
  - orchestration
related_skills:
  - karpathy-coding-guidelines
  - simplify-code
  - codebase-inspection
  - systematic-debugging
metadata:
  hermes:
    tags: [delegation, parallelism, subagents, concurrency, orchestration]
    related_skills: [karpathy-coding-guidelines, simplify-code, codebase-inspection, systematic-debugging]
---

# Parallel Delegation

Always use as much subagent parallelism as possible: the main agent's job is
orchestration, not execution. Every piece of work that a subagent can carry
should be handed off, batched into the same turn, so the main agent never sits
idle and the conversation keeps moving.

## Core Principles

1. **Question every task first**: *can a subagent do this?* If yes and it is
   independent of what you're doing, delegate it.
2. **Maximize parallelism**: N independent tasks → N `delegate_task` calls in
   the same assistant turn. Never spawn one at a time and never serialize
   independent work — sequential delegation multiplies wall-clock time for no
   benefit. Prefer many small, focused subagents over one big one.
3. **Stay unblocked**: between spawning and results, keep doing work that
   doesn't depend on the subagents. Do not hold your turn waiting for a result
   you don't need yet.
4. **Consume, don't redo**: when results arrive, use them — don't re-execute
   the delegated work yourself.

## When to Delegate

Delegate anything mechanical, long-running, parallelizable, or context-heavy:

- **Batch independent audits** — e.g., dependency/security/lint audits split
  per package or module, one subagent per scope (see Examples).
- **Script runs** — independent test scripts, formatting checks, or
  reproducible CLI commands that can run concurrently.
- **Repo scans** — `search_files` / codebase inspection over disjoint
  directories or areas, per-area.
- **Research & extraction** — web searches, page fetches, summarization,
  transcript-to-summary jobs.
- **Anything that doesn't need your in-flight judgment** — offload it so a
  long-running subagent finishes by the time you need its output.

Rule of thumb: if you can enumerate the units up front, fan out one subagent
per unit in a single turn.

## When NOT to Delegate

- **Trivial one-liners and single tool calls** — a file read, a simple grep,
  a one-command lookup. Delegation costs tokens (~20K per spawn) and a
  round-trip; beating it with a single tool call is faster and cheaper.
- **When you already have full context** — if the answer is already in your
  context or you're mid-way through exactly this work, finish it yourself.
  Re-delegating means re-transmitting everything for nothing.
- **When the task is the main agent's own judgment call** — decisions,
  tradeoffs, or steps the conversation's next move depends on immediately.
- **When spawn cost exceeds the work** — one quick `web_search` stays
  in-thread; ten independent searches go to subagents.

## How to Structure delegate_task Calls

```python
delegate_task(
    goal="<one concrete, verifiable outcome — what 'done' looks like>",
    context="""<fully self-contained brief: exact paths, exact commands,
    skills to follow, constraints, and the shape of the answer.
    Subagents cannot see your conversation context — put everything inline>""",
    output_schema={
        # structured fields so the result is machine-consumable, not prose
        "findings": {"type": "list", "description": "one item per issue"},
        "summary": {"type": "string", "description": "2-3 sentence verdict"},
    },
    toolsets=["terminal", "web_search"],  # minimal set the task needs
)
```

Each subagent gets:

- **A self-contained brief** — every detail inline; it cannot read your
  context. Include the skills it must load (e.g. tell it to follow
  `karpathy-coding-guidelines` for code work).
- **A single deliverable** — one outcome, stated as a concrete artifact,
  answer, or filled schema.
- **An `output_schema`** — structured results let you consume them directly
  and fan out the next batch without re-reading verbose summaries.
- **Explicit minimal toolsets** — grant only what the task needs.

## Examples

### Parallel per-package audits (from the repo audit runs)

Instead of one subagent walking every package sequentially, spawn one audit
subagent per scope in the same turn:

```python
for pkg in ["pkg-a", "pkg-b", "pkg-c"]:
    delegate_task(
        goal=f"Audit {pkg} for vulnerabilities and report findings",
        context=f"""
        Load the audit checklist. Run the pinned audit script:
          python scripts/audit.py {pkg} --full
        Only report issues with evidence (file:line or command output).
        Do not fix anything — report only.
        """,
        output_schema={
            "vulnerabilities": {"type": "list", "description": "each with file:line and severity"},
            "passed": {"type": "boolean"},
            "summary": {"type": "string"},
        },
        toolsets=["terminal", "file"],
    )
```

All three run concurrently; the main agent continues other work; results are
consumed per-package as they arrive. This is the pattern the audit results
demonstrated: parallel scopes finished far faster than one sequential sweep.

### Delegating code work (with karpathy-coding-guidelines)

When a subagent writes or changes code, its brief must include the discipline:

```python
delegate_task(
    goal="Fix the failing test in src/parser.py and make all tests pass",
    context="""
    Follow the karpathy-coding-guidelines skill: minimal changes, surgical
    diffs, no drive-by refactoring. Reproduce the failure first:
      pytest tests/test_parser.py -x
    Fix the root cause, then run the full suite:
      pytest -q
    Report the exact command output that proves the fix.
    """,
    output_schema={"changed_files": {"type": "list"}, "test_output": {"type": "string"}},
    toolsets=["terminal", "file", "code"],
)
```

The subagent owns verification and returns real output — never a claim of
"should work". The main agent checks the diff against the request without
re-running the work.

## Handling Results

- **Never poll** — don't idle-wait on a running subagent. Advance the next
  independent piece of the plan; check back when you have a reason to.
- **Treat results as out-of-order** — concurrent calls return independently;
  don't assume batch order.
- **Fan out the next batch** — consuming one result often unlocks the next
  wave of independent work. Pipeline: spawn → do main work → consume → spawn
  next wave.

## Anti-patterns

- ❌ **Serial delegation** — spawning independent subagents one per turn.
- ❌ **Doing delegated work yourself** — you spawned it; let it finish.
- ❌ **Blocking on results** — idle waiting while other work is pending.
- ❌ **Under-delegating** — running long or context-heavy work in the main
  thread that a subagent could carry.
- ❌ **Over-delegating** — a subagent for a one-line lookup the main agent can
  do in one tool call.

## Pitfalls

- Subagents may **not** inherit your conversation context or plugin-defined
  tools. Every requirement goes in the `context` string; toolsets are passed
  explicitly.
- Each spawn costs tokens (~20K) and a round-trip — parallelism pays off for
  independent batches, not for work you could finish in one call yourself.
- Concurrent results arrive out of order — key them by their `goal`, never by
  position.

## Verification

The skill worked if, at the end of a multi-task session:

- [ ] Independent tasks were spawned in one turn, not one per turn
- [ ] The main agent did useful work between spawn and results (never idle-polled)
- [ ] Every delegated brief was self-contained (paths, commands, skills, schema)
- [ ] Results were consumed without redoing the work, and the next batch was fanned out
- [ ] Trivial single-call work stayed in-thread; nothing was delegated pointlessly