# Hermes Webtop — Agent Guidelines

## Quickstart

1. **Load these skills first** (via `skill_view`):
   - `karpathy-coding-guidelines` — surgical minimal diffs, verify with real output
   - `docker-test-shell` — clean-container integration tests
   - `codespace-gh-auth` — GitHub token for this Codespace
   - `ci-lint-check` / `ci-log-capture` — CI validation + log preservation
   - `mnemon-recall` / `mnemon_remember` — session memory

2. **Always verify with real output** before claiming success:
   - CI runs, builds, test Docker images, self-check health — always check exit codes and artifact logs
   - If a tool call fails, say so plainly; do not fabricate results

3. **Phase-based work** — never jump phases:
   - **Phase 1**: ModelRelay → 9Router (port 7352) — ✅ DONE
   - **Phase 2**: PI branch fix + dependency bumps — ✅ DONE
   - **Phase 3**: .agents/skills port — ✅ DONE

## Project Structure (key paths)

| Path | Purpose |
|------|---------|
| `docker/Dockerfile` | Multi-stage build; ARGs: PI_VERSION, NINEROUTER_VERSION, OMNIROUTE_VERSION, NODE_VERSION, etc. |
| `docker/start-ninerouter.sh` | 9Router launch + health poll (`/api/health`, 300s) + inline config |
| `docker/9router-config.sh` | **Deleted** — config logic inlined into start-ninerouter.sh |
| `docker/self-check.sh` | Validates all services; probes `/v1/models` for 9Router (not just `/`) |
| `docker/pi-settings.json` | Pi install config — `git:github.com/gitricko/pi-failover@main` |
| `docker/pi-models.json` | Provider chain `9router` / `omniroute` |
| `.agents/skills/` | Repo-portable skills (ci-lint-check, ci-log-capture, docker-test-shell) |
| `~/.hermes/skills/minions/` | Global minions skills (do NOT edit these) |
| `~/.hermes/memories` | Mnemon graph — persist insights across sessions |

## Core Procedures

### 9Router Migration (Phase 1)
**Root Cause Pattern**: `/config/.9router/` state dir didn't exist at boot → EACCES on `jwt-secret/model-catalog` → every stateful endpoint (login, combos, models) returned 500.

**Fix Pattern** (always-run before `nohup 9router ...`):
```
mkdir -p /config/.9router
chown -R abc:abc /config/.9router
```

**Health Probing**: `/api/health` is stateless; it may return 200 while `/api/auth/login` and `/api/combos` 500. Always probe `/v1/models` for 9Router health.

**Config Timing**: s6 init scripts run *before* the daemon alphabetically. Moving config from s6 init.d to `/usr/local/bin/` and calling it explicitly from `start-ninerouter.sh` after the health poll is the correct pattern.

**`--log` Flag**: Always add `--log` to `9router` launch for visibility into internal errors (EACCES, etc.). Without it, only HTTP 500 is visible.

### PI Branch Fix (Phase 2)
- `pi-settings.json`: `git:github.com/gitricko/pi-failover@hermes-impl` → `@main`
- `start-pi.sh`: same branch fix
- `docker/Dockerfile`: `PI_VERSION 0.85.1 → 0.87.1`, `NODE_VERSION 26.7.0 → 26.10.0`

### .agents/skills Port (Phase 3)
Copy core CI/Docker skills from `~/.hermes/skills/minions/` to `.agents/skills/` for repo portability:
- `ci-lint-check` / scripts + references
- `ci-log-capture` / scripts + references
- `docker-test-shell` / scripts + references
- `parallel-delegation` — already present

### Version Checking
Run `scripts/check-deps.sh` to systematically check npm package versions against latest on registry.

### Self-Check Grep Context
`docker/self-check.sh`: use `-A2` (not `-A1`) when grepping `^model:` and `^provider:` from Hermes config, to capture the full `key: value` pair across two lines.

## Core Principles

### 1. Load skills before acting
Never guess at commands. Always `skill_view(name='...')` first for any task involving:
- Configuration changes
- Dockerfile modifications
- CI debugging
- Mnemon integration

### 2. Verify with real output
CI runs, builds, test Docker images, self-check health — always check exit codes and artifact logs.
- If a tool call fails, report the actual error — do not fabricate success
- Terminal output over 50KB auto-saves to a file; the full text rides in the result

### 3. Phase gates — never skip
- **Phase 1**: ModelRelay → 9Router ✅
- **Phase 2**: PI branch fix + dep bumps ✅
- **Phase 3**: .agents/skills port ✅
Do not start Phase 2 before Phase 1 is green; do not start Phase 3 before Phase 2.

### 4. State dirs must exist before daemon launch
Learned the hard way: `/config/.9router/` didn't exist at boot → EACCES on jwt-secret/model-catalog → every stateful endpoint returned 500.
**Fix pattern**: `mkdir -p /config/.9router && chown -R abc:abc /config/.9router` before `nohup 9router ...`

### 5. Health endpoint ≠ functional endpoint
`/api/health` is stateless; it returned 200 while `/api/auth/login` and `/api/combos` 500'd.
**Fix**: self-check probes `/v1/models` for 9Router health, not just the base URL.

## Skills Load Order (always)

```
1. karpathy-coding-guidelines       — diff discipline + verify with real output
2. docker-test-shell                — clean-container integration tests
3. codespace-gh-auth                — GitHub token extraction
4. ci-lint-check                    — pre-commit CI lint validation
5. ci-log-capture                   — preserve boot logs across CI runs
6. mnemon-recall                    — fetch session memories
```

### When to delegate vs do yourself
- **Mechanical multi-step** (N commands, no reasoning) → `execute_code` + `terminal`
- **Reasoning-heavy** (multiple sub-tasks, research) → `delegate_task` with fan-out
- **Single tool call** → call directly, no delegation

### Mnemon memory
- **`memory`** store: who the user is, stable env facts, standing conventions
- **`mnemon_remember`**: insights that apply to EVERY session regardless of task
- **`mnemon_recall`**: query by natural language; intent WHY/WHEN/ENTITY/GENERAL
- Keep memory entries small (this note budget is ~2200 chars)
- Procedures and workflows go in skills, not memory

## Dependency Checking Pattern

When modifying Dockerfile or installing packages:

1. Check the project manifest: `docker/Dockerfile` ARGs
2. `npm view <pkg> version` (if npm available) — **not always available in this sandbox**
3. If npm is unavailable: use version from previous commit or Dockerfile ARG
4. After any change: `git diff HEAD~1` to verify only intended files changed
5. Run: `bash -n <script>` for syntax sanity
6. Commit, push, monitor CI — do not claim "works" without CI green

### Version bump pattern (from Phase 2)
- `NODE_VERSION 26.7.0 → 26.10.0`
- `PI_VERSION 0.85.1 → 0.87.1`
- Always check `npm view <pkg> version` if available, otherwise use semantic LTS progression
- Commit message: `VERSION: X.Y.Z → X.Y.Z`

## Common Pitfalls (from this session)

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| EACCES on `/config/.9router/jwt-secret` | State dir didn't exist at boot | `mkdir -p /config/.9router && chown -R abc:abc` |
| 9Router HTTP 500 on all APIs | Config never ran (disabled) | Re-enabled `bash /usr/local/bin/9router-config` in start-ninerouter.sh |
| jq parse error on login | Server returned non-JSON (HTML error page) | Added `2>&1 || echo '{}'` + `if ! echo "$LOGIN_RESPONSE" | jq -e '.success // empty'` |
| while-true restart loop | Cargo-culted from start-modelrelay.sh | Replaced with simple `nohup ... &` + health poll |
| Mnemon Integration Test skip | Self-check failed before reaching Mnemon | Fix self-check → Mnemon passes |
| PI install branch not found | `hermes-impl` branch missing | Changed to `@main` in pi-settings.json + start-pi.sh |
| `--log` flag reveals hidden errors | Without it, only saw HTTP 500 | Add `--log` to 9Router launch for visibility |

## Deliverable Checklist (before saying "done")

- [ ] `git diff` shows only intended changes
- [ ] `bash -n` passes on all modified .sh files
- [ ] CI run completes (`build-test` + `Test Docker image` + `Mnemon Integration Test`)
- [ ] 9router.log confirms no EACCES
- [ ] Mnemon integration test passes (or documented caveat)
- [ ] Mnemon memory updated with new lessons
- [ ] No agent.md or skill content fabricated — all claims backed by tool output

## What NOT to do

- ❌ Never fabricate tool output or CI results
- ❌ Never claim "works" without real output verification
- ❌ Never skip the phase gate (Phase 1 → 2 → 3)
- ❌ Never modify another profile's skills/plugins/cron/memories without explicit direction
- ❌ Never ignore `set -euo pipefail` consequences — know what breaks
- ❌ Never commit without running `git diff --stat` first

## File this session's lessons

- `mnemon_remember` entry: see above — "Lessons Learned" section
- Skill: `karpathy-coding-guidelines` already loaded
- Memory: `~/.hermes/memories/` — compact, high-signal facts only

---

*This file lives at `AGENTS.md` in the repo root and is loaded on every new agent session. Future agents should read this before any task, then load the skills listed in "Skills Load Order" before beginning work.*

*Adapted from the Firstmate AGENTS.md (https://github.com/gitricko/firstmate-codespace/blob/main/AGENTS.md) — principle: store knowledge useful to almost every future agent session in this project.*
