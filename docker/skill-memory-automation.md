---
name: memory-automation
description: "Automated mnemon memory persistence workflow — recall on start, recall before each turn, auto-save after each response via delegated subagent."
version: 1.4.0
author: hermes-webtop
tags:
  - memory
  - mnemon
  - persistence
  - automation
---

# Memory Automation

Automates the persistent-memory workflow for Hermes using Mnemon graph memory. Used by `.hermes.md` instructions to keep every session primed with context.

## Mnemon Quick Reference

### Mnemon Tool Signatures

```python
mnemon_remember(text, category, importance, entities, tags)  # Plugin tool — direct call
mnemon_recall(query, intent, limit)                          # Plugin tool — direct call
mnemon_forget(insight_id)                                    # Plugin tool — direct call
```

These are real Hermes plugin tools, not pseudocode. See [Save Patterns](#save-patterns) for when to use them directly vs via delegated subagent.

### Categories (for `category` parameter)

| Category | When to use |
|----------|-------------|
| `fact` | Objective information about the user, project, or environment |
| `preference` | User's likes, dislikes, stylistic choices, workflow preferences |
| `decision` | Architectural decisions, tool choices, design decisions |
| `insight` | Non-obvious findings, troubleshooting steps, workarounds |
| `context` | Session-level context that's useful across sessions |
| `general` | Anything that doesn't fit above |

### Importance Levels

| Level | When to use |
|-------|-------------|
| 5 | Critical — user identity, core preferences, security constraints |
| 4 | Important — project goals, recurring preferences, key constraints |
| 3 | Normal — useful context, typical insights |
| 2 | Minor — nice-to-know details |
| 1 | Trivial — barely worth saving (use rarely) |

## Recall Patterns

### Full Context Load (Session Start)

```python
# Called by the SessionStart hook
mnemon_recall(query="", intent="GENERAL", limit=20)
```

This loads the 20 most relevant past insights into context. No specific query needed — just a broad sweep of everything mnemon has stored.

### Topic-Specific Recall (Before Responding)

```python
# If the hook returns nothing but the topic references past work:
mnemon_recall(query="<topic keywords>", intent="GENERAL", limit=10)
```

Use the user's message topic as the query. Include key terms, project names, and any domain-specific vocabulary.

### Intent-Targeted Recall

```python
# When you need to understand WHY a decision was made:
mnemon_recall(query="<topic>", intent="WHY", limit=5)

# When you need to know WHEN something happened:
mnemon_recall(query="<topic>", intent="WHEN", limit=5)

# When you need info about a specific entity:
mnemon_recall(query="<entity name>", intent="ENTITY", limit=5)
```

## Save Patterns

### Direct Tool Call (Preferred for Simple Saves)

`mnemon_remember` is a real Hermes plugin tool exposed by the `gitricko/hermes-plugin-mnemon` plugin. Call it directly from your toolset — no subagent, no CLI invocation needed:

```python
mnemon_remember(
    text="User prefers concise responses and bullet points over prose.",
    category="preference",
    importance=4,
    entities=["gitricko"],
    tags=["communication-style","user-preference"]
)
```

**Use direct calls when:**
- Saving a single fact or preference inline during a response
- The save is straightforward — no extraction, no multi-item batch
- You're already in a turn; just batch the tool call with whatever else you're doing

The tool wraps the `mnemon` CLI. No MCP server, no subagent.

### Delegated Save (Bulk or After Complex Responses)

For bulk saves (3+ items) or when context is tight, delegate to a subagent with `toolsets=["terminal"]`. The subagent uses the `mnemon remember` CLI since plugin tools may not propagate to child sessions:

```python
delegate_task(
    goal="Save insights to mnemon memory",
    context="""Save the following to mnemon memory:

1. text="User prefers bullet-point summaries over paragraphs.",
   category="preference", importance=4,
   entities=["gitricko"], tags=["communication-style"]

2. text="The project uses FastAPI with PostgreSQL.",
   category="fact", importance=3,
   entities=["project-name"], tags=["tech-stack"]

For each item run: mnemon remember "<text>" \\
  --cat <category> --imp <N> \\
  --entities e1,e2 \\
  --tags "t1,t2"
Binary: /usr/local/bin/mnemon.""",
    toolsets=["terminal"]
)
```

**Use delegated saves when:**
- Saving 3+ items at once
- The save requires extraction or reasoning (e.g. "pick out all preferences from this dialog")
- You're low on context tokens and want the work offloaded

### Decision Guide: Direct vs Delegated

| Condition | Method | Reasoning |
|-----------|--------|-----------|
| 1–2 items, simple | Direct `mnemon_remember()` tool call | Zero overhead — inlined with response |
| 3+ items | Delegate to subagent with CLI | Worth the ~20K token spawn cost for bulk |
| Save requires extraction/analysis | Delegate to subagent | Extraction logic is better offloaded |
| Already doing other tool calls | Batch `mnemon_remember()` with them | Same turn, no extra cost |
| `.hermes.md` says "delegate subagent" (blanket) | Follow the 1–2 / 3+ split above instead | Blanket delegation burns ~20K tokens per trivial save (e.g. "tmr" → timing detail). Proactively update `.hermes.md` to the two-tier system. If user insists on delegation-only, follow their explicit instruction — but default is cost-efficient direct calls. |
| User explicitly asks for delegation | Always delegate, even for simple saves | User preference overrides efficiency — be transparent about the token cost so they can make an informed choice. |

### Batch Operations with memory() Fallback

For structured preference data that needs the memory() tool (target='user' or 'memory'):

```python
memory(
    target="user",
    operations=[
        {"action": "add", "content": "User prefers dark mode terminals."},
        {"action": "replace", "old_text": "old stale fact", "content": "updated fact"}
    ]
)
```

## When to Auto-Save (After Every Response)

After every user-facing response, scan the exchange for anything on this list:

| Signal | What to save |
|--------|-------------|
| User stated a preference | Save as `preference` |
| User made a decision | Save as `decision` |
| User corrected you | Save as `preference` or `fact` |
| You discovered a workaround | Save as `insight` |
| User revealed personal info | Save as `fact`, importance=5 |
| User said "remember this" | Save whatever follows |
| Project architecture detail | Save as `fact` |
| Tool configuration quirk | Save as `insight` |

**When in doubt, save it.** Extra memories are cheap; missing ones are expensive.

## What NOT to Save

- Code the repo already tracks (git history)
- Public API docs or well-known facts
- Transient state ("how are you?", current time)
- Things already in `.hermes.md`, `AGENTS.md`, or other config files

## Example: Full Turn Cycle

```
Session Start → mnemon_recall("", limit=20) → preloaded context

User: "I prefer using ruff over black for formatting."
  → Hook: auto mnemon_recall("ruff black formatting", limit=10)
  → Respond
  → Direct: mnemon_remember(
       text="User prefers ruff over black for Python formatting.",
       category="preference", importance=4,
       entities=["gitricko"], tags=["formatting","python"]
     )

User: "Remember the project uses Python 3.13"
  → Respond
  → Direct: mnemon_remember(
       text="Project uses Python 3.13.",
       category="fact", importance=4,
       entities=["gitricko"], tags=["python","project-setup"]
     )

User: "Also save these three things: ..."
  → Respond
  → Delegate: bulk save via subagent (3+ items)
```

## Pitfalls

### `mnemon_remember` IS a Real Tool (Plugin-Exposed)
The function `mnemon_remember(...)` is a real Hermes tool, exposed by the `gitricko/hermes-plugin-mnemon` plugin. Call it directly from your toolset — no CLI needed.

`mnemon_recall(...)` and `mnemon_forget(...)` may also be available depending on what the plugin exposes. Check your tool list at session start.

Subagents may NOT inherit plugin-defined tools. If delegating a save, pass `mnemon remember` CLI commands in context and set `toolsets=["terminal"]` so the subagent runs via shell.

### Real CLI Flags vs Tool Parameters (Subagent Use Only)

When delegating to a subagent, it runs the `mnemon` CLI — not the plugin tool. The CLI uses different flags than the tool parameters:

| Tool parameter | CLI flag | Notes |
|---|---|---|
| `text` | positional arg | First argument, not a flag |
| `category` | `--cat` | e.g. `--cat preference` |
| `importance` | `--imp` | e.g. `--imp 4` |
| `entities` | `--entities` | Comma-separated: `entity1,entity2` |
| `tags` | `--tags` | Comma-separated: `tag1,tag2` |

### Sub-Agent Needs `terminal` Toolset
Delegated saves require `toolsets=["terminal"]` — the sub-agent runs `mnemon` via the shell since plugin tools don't propagate to child sessions. Omitting this or using a wrong toolset leaves the sub-agent with no way to run the CLI.

### Load This Skill Proactively
This skill must be loaded at the start of every session (via `skill_view(name='memory-automation')`). Do not rely on `.hermes.md` reminders to trigger it — if the skill isn't loaded, you won't follow the workflow. Add it to the start-of-session routine.

### Don't Confuse `mnemon_remember` with `memory()`
`mnemon_remember()` (plugin tool) → stores to **Mnemon graph DB** — durable, queriable, multi-session.

`memory()` (built-in Hermes tool) → stores to **agent memory** — injected every turn, bounded at 2.2K chars.

They target different stores. Use `mnemon_remember()` for Mnemon entries and `memory()` for the Hermes built-in memory. The `[MEMORY]` and `[USER PROFILE]` sections injected at the top of every prompt are rendered from the `memory()` tool's data — they are NOT part of `.hermes.md`. Don't conflate the two tools or their targets.

### `.hermes.md` Says Delegate But It's Wasting Tokens — What To Do
`.hermes.md` often says "delegate subagent to mnemon_remember" as a blanket instruction. The skill's Decision Guide says direct calls are fine for simple saves. Follow the Decision Guide's cost-aware split instead (direct for 1–2 simple items, delegate for 3+/complex). Propose updating `.hermes.md` to the two-tier system. If the user explicitly prefers delegation-only, defer — but be transparent about the ~20K token cost per spawn so it's an informed choice.
