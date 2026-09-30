---
name: ci-log-capture
description: Use when test scripts redirect probe output to /dev/null, hiding failure details. Replace with file captures that feed CI artifacts.
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [ci, logging, debugging, artifacts, github-actions]
    related_skills: [ci-debugging, docker-test-shell, github-codespace]
---

# CI Log Capture — Replace `/dev/null` with Artifact Files

Every `>/dev/null 2>&1` is a debug dead-end. Capture to files that auto-upload
as CI artifacts so failures are self-documenting.

## The problem

```bash
# BEFORE: failure body goes to void
if curl -sf https://api.example.com/health >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"  # but WHY? 400? 401? 500? timeout?
fi
```

When this fails in CI, you get "FAILED" with zero context. The HTTP status,
response body, and headers are gone.

## The pattern: `run_and_log`

```bash
# 1. Ensure log dir exists (matches workflow env)
CI_LOGS_DIR="${CI_LOGS_DIR:-/tmp/ci-logs}"
mkdir -p "${CI_LOGS_DIR}"

# 2. Helper: run command, capture to file, print on failure
run_and_log() {
    local test_name="$1"; shift
    local log_file="${CI_LOGS_DIR}/${test_name}.log"
    if "$@" >"${log_file}" 2>&1; then
        log_info "${test_name} — OK"
        return 0
    else
        log_error "${test_name} — FAILED (see ${log_file})"
        cat "${log_file}"   # immediate CI visibility
        return 1
    fi
}

# 3. Replace:
# BEFORE: if cmd >/dev/null 2>&1; then
# AFTER:  if run_and_log "endpoint-name" cmd; then
```

## Artifact integration

The workflow must upload `${CI_LOGS_DIR}` with `if: always()`:

```yaml
# .github/workflows/ci.yml
- name: Upload diagnostic logs
  if: always()
  uses: actions/upload-artifact@v7
  with:
    name: ci-logs-${{ github.run_id }}
    path: ${{ env.CI_LOGS_DIR }}/
    if-no-files-found: warn
    retention-days: 7
```

Name the log files so they sort logically in the artifact zip:
- `hermes-version.log`
- `omniroute-models.log`
- `ninerouter-chat.log`
- `boot.log`

## Probe classification — what to capture vs keep silent

| Probe type | Capture? | Notes |
|------------|----------|-------|
| Version checks (`--version`) | ✅ YES | Confirms binary integrity |
| Health endpoints (`/healthz`) | ✅ YES | Shows HTTP status on failure |
| Model lists (`/v1/models`) | ✅ YES | Shows count + any error body |
| Chat completions | ✅ YES | **Critical** — shows 400/401/403 from upstream |
| Preconfig steps (login, setup) | ✅ YES | Shows which step failed |
| Cleanup (`docker rm -f`) | NO — keep `>/dev/null 2>&1` | Expected noise |
| Container startup wait | NO — keep `>/dev/null 2>&1` | Expected noise |
| Extension list (`pi skill list`) | NO — keep stderr only | Too verbose for artifacts |

## CI workflow requirements

For this pattern to work, the calling CI job must:
1. Set `CI_LOGS_DIR` env (e.g. `/tmp/real-install`, `/tmp/dts-logs`)
2. Have an `if: always()` artifact upload step targeting that path
3. Match `retention-days` to your debugging window (7 days is typical)

The repo already has this for Real Install and DTS — just ensure test
scripts write to it.

## Real-world example (from this repo)

The `test_cli_integration.sh` chat completion probes (lines 318, 325)
were `>/dev/null` — hiding the exact OC provider 400/401/403 response.
After replacing with `run_and_log "omniroute-chat" curl ...`, the CI
log showed the full JSON error body on failure, and the artifact
contained it for download. No more guessing what the provider returned.

## When NOT to use

- Probes that run thousands of times in a tight loop (log file thrashing)
- Pure cleanup commands where failure is expected and irrelevant
- Situations where `CI_LOGS_DIR` isn't available (standalone scripts)

In those cases, keep the `/dev/null` but add a comment explaining why.