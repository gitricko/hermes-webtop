---
name: dependency-version-check
description: Check all Dockerfile ARG-pinned dependency versions against their upstream sources before push/merge.
version: 0.1.0
author: gitricko, Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [dependencies, versions, docker, npm, github, pre-merge, check-deps]
    related_skills: [ci-lint-check, docker-test-shell]
---

# Dependency Version Check Skill

Runs `scripts/check-deps.sh` — compares every dependency version pinned in
`docker/Dockerfile` (the single source of truth) against its upstream registry.

**No hardcoded versions in the script** — it reads Dockerfile ARGs at runtime,
so the Dockerfile is always the authoritative place to bump versions.

## When to Use

- **Before every push / PR merge** that touches `docker/Dockerfile`
- When CI build fails on a version-specific error
- Periodically to check for upstream releases
- After editing any `ARG *_VERSION` line

## How to Run

```bash
bash scripts/check-deps.sh
```

Expected output format:

```
=== Hermes Webtop Dependency Check ===
(current versions read from docker/Dockerfile ARGs)

NPM packages:
  9router            current=0.5.91 | latest=0.5.91 [OK]
  omniroute          current=3.8.51 | latest=3.8.51 [OK]
  pi-coding-agent    current=0.87.1 | latest=0.87.1 [OK]

GitHub-release binaries:
  hermes-agent       current=2026.9.24 | latest=2026.9.24 [OK]
  node               current=26.10.0 | latest=26.10.0 [OK]
  ollama             current=0.35.0 | latest=0.35.0 [OK]
  code-server        current=4.139.1 | latest=4.139.1 [OK]
  mnemon             current=0.2.9 | latest=0.2.9 [OK]
  herdr              current=0.7.4 | latest=UNAVAILABLE
```

Status markers:
- `[OK]` — current == latest
- `[UPDATE AVAILABLE]` — a newer stable release exists → bump the Dockerfile ARG
- `UNAVAILABLE` — upstream source query failed (no tags, rate limit, or different repo layout)

## What It Checks

| Check | Source | Function |
|-------|--------|----------|
| 9router, omniroute, pi-coding-agent | npm registry | `npm_latest` |
| hermes-agent, ollama, code-server, mnemon, herdr | GitHub tags API | `gh_latest` |
| node | nodejs.org dist index (same major line) | `node_latest` |

## Pre-release Filtering

`gh_latest` filters out pre-release tags: `rc`, `beta`, `alpha`, `preview`,
`pre-`, `dev`, `nightly`, `canary`, `next` (case-insensitive, anywhere in tag
name). Leading `v` is stripped. This prevents false "update available" on
tags like `v0.40.0-rc0`.

`node_latest` compares only plain `x.y.z` versions in the same major line.

## Adding a New Dependency Check

1. Add the `ARG` to `docker/Dockerfile`
2. Add a version variable at the top of `scripts/check-deps.sh`:
   ```bash
   NEWPKG_VERSION="$(arg NEWPKG_VERSION)"
   ```
3. Add a `check` call in the appropriate section:
   ```bash
   check "newpkg" "${NEWPKG_VERSION}" "$(npm_latest newpkg)"
   # or for GitHub-release binaries:
   check "newpkg" "${NEWPKG_VERSION}" "$(gh_latest owner/repo)"
   ```

`herdr` (`ogulcancelik/herdr`) is pinned intentionally — its tags API returns
`UNAVAILABLE` due to repo layout; bump manually.

## Related

- `scripts/check-deps.sh` — the implementation
- `.github/workflows/docker-publish.yml` — uses Dockerfile ARGs at build time
- `AGENTS.md` — Dependency Checking Pattern section
