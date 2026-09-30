---
name: ci-lint-check
description: Run pre-commit CI lint validation locally before pushing to avoid GitHub Actions failures.
version: 0.1.0
author: gitricko, Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [ci, lint, pre-commit, github-actions, validation]
    related_skills: [codespace-persistent-symlinks, memory-automation]
---

# CI Lint Check Skill

Run the full CI lint validation locally before committing or creating a PR. This mirrors the `lint-check` job in `.github/workflows/ci.yml` and catches all format/validation issues that would fail CI.

## When to Use

- **Before every commit** that touches `skills/**`, `wiki/**`, `mnemon/**`, `memories/**`, or `*.sh`
- **Before creating a PR** to ensure CI passes
- When CI fails and you need to debug locally

## Prerequisites

- `markdownlint-cli` (auto-installed by script)
- `python3` (for Mnemon seed validation)
- `bash` (for shell syntax checks)

## How to Run

```bash
# Quick one-liner (runs all checks):
bash skills/ci-lint-check/scripts/ci_lint_check.sh

# Or step by step:
bash skills/ci-lint-check/scripts/ci_lint_check.sh --markdown-only
bash skills/ci-lint-check/scripts/ci_lint_check.sh --skills-only
bash skills/ci-lint-check/scripts/ci_lint_check.sh --wiki-only
bash skills/ci-lint-check/scripts/ci_lint_check.sh --mnemon-only
bash skills/ci-lint-check/scripts/ci_lint_check.sh --shell-only
bash skills/ci-lint-check/scripts/ci_lint_check.sh --symlink-only
```

## What It Validates

| Check | Files | CI Job |
|-------|-------|--------|
| Markdown lint | `wiki/*.md`, `skills/*/SKILL.md`, `.hermes.md`, `README.md` | `lint-check` |
| SKILL.md structure | All skills in `skills/*/SKILL.md` | `lint-check` |
| Wiki INDEX.md consistency | Every `.md` in wiki/ referenced in INDEX.md | `lint-check` |
| Mnemon seed.json | `mnemon/seed.json` schema | `lint-check` |
| Root shell syntax | `*.sh` | `lint-check` |
| Skill shell syntax | `skills/*/scripts/*.sh` | `lint-check` |
| Symlink persistence | Tracked dirs + boot script symlink logic | `lint-check` |

## Procedure

### 1. Install dependencies (first run only)
```bash
npm install -g markdownlint-cli
```

### 2. Run full validation
```bash
bash skills/ci-lint-check/scripts/ci_lint_check.sh
```

### 3. Fix any reported issues
- Markdown lint: fix reported line/column issues
- SKILL.md: ensure YAML frontmatter with `name:` field
- Wiki: add missing articles to INDEX.md table
- Mnemon: `python3 mnemon/validate-seed.py mnemon/seed.json`
- Shell: `bash -n <script>` to see syntax errors
- Symlinks: ensure boot scripts create proper symlinks

### 4. Commit and push
```bash
git add -A
git commit -m "your message"
git push
```

## CI Behavior

| Changed Paths | CI Job | Duration |
|---------------|--------|----------|
| `skills/**` | `lint-check` | ~30s |
| `wiki/**` | `lint-check` | ~30s |
| `mnemon/**` | `lint-check` | ~30s |
| `memories/**` | `lint-check` | ~30s |
| `*.sh` | `lint-check` | ~30s |
| `.github/workflows/**`, `install.sh`, `boot.sh`, `self-check.sh` | `full-build` | ~15min |

**Only infrastructure changes trigger full-build.** Content changes (skills, wiki, mnemon, memories, shell scripts) run the fast lint-check only.

## Dev/Prod Parity Principle

**The local script IS the CI job.** The `lint-check` workflow step delegates entirely to `ci_lint_check.sh`:

```yaml
- name: Run local CI lint check script
  run: |
    npm install -g markdownlint-cli
    bash skills/ci-lint-check/scripts/ci_lint_check.sh
```

This guarantees identical validation in both environments. Never duplicate validation logic in CI YAML — the skill script is the single source of truth.

## Pitfalls

- **Don't skip this** — CI will fail and you'll waste time debugging in GitHub Actions
- **Run from repo root** — paths are relative to `/workspaces/.minions`
- **markdownlint config** is embedded in the script (matches CI config)
- **Mnemon seed validation** requires the validator script to exist
- **Symlink check** validates boot script logic, not actual runtime symlinks
- **MD034 / no-bare-urls** — raw URLs in any `.md` fail lint with `error MD034/no-bare-urls Bare URL used`. Wrap them in angle brackets: `<https://example.com>` not `https://example.com`. This broke PR #3 (two bare URLs in a SKILL.md References block and a references/*.md). The markdownlint config here does NOT disable MD034, so every URL must be bracketed.

## Integration with Git Hooks (Optional)

Add to `.git/hooks/pre-commit`:
```bash
#!/bin/bash
bash skills/ci-lint-check/scripts/ci_lint_check.sh || exit 1
```

## References

- `.github/workflows/ci.yml` — source of truth for CI jobs
- `wiki/github-actions-testing-plan.md` — CI design doc
- `skills/codespace-persistent-symlinks/SKILL.md` — symlink architecture

## Known Limitations
- **Symlink check (7/7)** requires `boot.sh` to contain the skills/memories wiring patterns (Phases 16–18). Until then, run with `--shell-only` or `--skills-only` to skip.
- **Markdown lint (1/7)** requires `markdownlint-cli` (`npm install -g markdownlint-cli`). CI installs it automatically.

## Verification

```bash
# Should output "=== ALL CHECKS PASSED ==="
bash skills/ci-lint-check/scripts/ci_lint_check.sh
```

## For Future Agents

**MANDATORY**: Run this skill before ANY commit or PR that modifies:
- Skills (`skills/**`)
- Wiki (`wiki/**`)
- Mnemon (`mnemon/**`)
- Memories (`memories/**`)
- Devcontainer shell scripts (`*.sh`)

```bash
# One command before commit:
bash skills/ci-lint-check/scripts/ci_lint_check.sh
```