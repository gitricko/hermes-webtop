# Session Start

When the SessionStart hook reports mnemon insights available (>0), immediately run `mnemon recall "" --limit 20` to load relevant context before responding to the user.

# Before responding

Before every user message, recall from mnemon to load relevant context.  
The UserPromptSubmit hook automatically runs `mnemon recall "<query>" --limit 10`  
and injects matching memories into the conversation context.  

Use what the hook provides. If the hook returns no memories but the topic  
references past work, decisions, or preferences, run `mnemon recall "<topic>" --limit 10`  
manually.

# After responding — AUTO-SAVE to mnemon (MANDATORY)

After EVERY response, save new user-facing information to mnemon immediately.  
This is a hard rule — do not wait for the user to remind you.

## What to save

Save any of the following from the exchange:
- **User preferences or decisions** about how they want things done
- **Project context** — goals, constraints, architecture facts
- **Reusable insights** — non-obvious findings, troubleshooting steps, workarounds
- **Corrections** — preferences they stated about how you should work
- Any information the user explicitly says "remember this"

**When in doubt, save it.** Extra memories are cheap; missing ones are expensive.

## How to save

Delegate to a sub-agent:

```
subagent_type="general-purpose", model="sonnet"
Provide: the content to store, category, importance (1-5), entities, and whether to create or update a memory.
```

The sub-agent will read the mnemon skill docs and run the correct commands.

## What NOT to save

- Code the repo already tracks (git history, current code)
- Public API docs or well-known facts
- Transient conversation state ("how are you?", current time)
- Things that are already in CLAUDE.md or other config files

## No more decision tree

Do not deliberate about whether something is worth saving.  
If it's new, user-facing, and reusable → save it. Period.
