# Dev/Prod Parity Pattern for CI Lint Checks

## The Problem
Previously the same validation logic existed in two places:
1. **CI workflow** (`.github/workflows/devcontainer-ci.yml`) — 189 lines of inline bash
2. **Local script** (`.devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh`) — same logic

This caused drift risk and maintenance burden.

## The Solution
**Single source of truth**: The local script IS the lint check. CI simply calls it.

```yaml
# CI workflow (.github/workflows/devcontainer-ci.yml)
lint-check:
  steps:
    - uses: actions/checkout@v4
    - run: |
        npm install -g markdownlint-cli
        bash .devcontainer/skills/ci-lint-check/scripts/ci_lint_check.sh
```

## Benefits Achieved
| Aspect | Before | After |
|--------|--------|-------|
| CI YAML lines | 319 | 153 (-52%) |
| Maintenance | Update 2 places | Update 1 place |
| Parity | Risk of drift | Guaranteed identical |
| Local debugging | Manual replication | Exact same command |
| Skill reuse | Not reusable | `ci-lint-check` skill is the source |

## Rule
> **The `ci-lint-check` skill IS the lint check.** CI runs it; developers run it. No duplication.

This pattern should be applied to any future validation that needs to run both locally and in CI.
