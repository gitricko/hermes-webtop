---
name: docker-test-shell
description: Use when testing in a clean throwaway container.
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
---

# Docker Test Shell (`dts`)

Test ANY tool inside a fresh, throwaway Linux container — never trust the host.

## The one concept

> Test inside a throwaway container so your own environment's installed libs, stale state, and services do not pollute the test.

That is the entire tool. No test framework, no schema, no verify primitives. Just: get me into a clean container with my repo mounted in, and let me run commands. Target logic is PLAIN SHELL composed of `dts exec` + bash checks.

## Quickstart

```bash
# from the repo you want to test (it gets bind-mounted at /src)
./scripts/dts.sh up
./scripts/dts.sh exec "bash /src/install.sh"
./scripts/dts.sh exec "my-tool --version"
./scripts/dts.sh clean
```

For convenience, add the script dir to PATH or alias `dts`:
```bash
export PATH="$PWD/scripts:$PATH"   # or symlink dts.sh -> /usr/local/bin/dts
```

## Commands

| Command | Job |
|---------|-----|
| `dts up` | Create container (fresh base, repo bind-mounted at `/src`, uid-1000 user). Installs NOTHING. |
| `dts exec "<cmd>"` | Run `<cmd>` inside the container as the uid-1000 user, `bash -l`. TTY-aware. |
| `dts apt "<pkgs>"` | Run `apt-get update && install -y <pkgs>` as ROOT. The one privileged path (apt needs root; normal user can't). |
| `dts shell` | Drop into an interactive shell (`-it`). For a human at a terminal. |
| `dts clean` | Remove the container (no orphans). |
| `dts status` | Show container state + note the mount is present. |

## When to use `dts exec` vs raw `docker exec`

| Scenario | Use | Why | Notes |
|----------|-----|-----|-------|
| Normal test commands (build, version check, API call) | `dts exec` | Runs as uid-1000, `bash -l`, `-i` no `-t` — matches CI/Codespace parity | |
| Install apt packages (`apt-get install`) | `dts apt` | Dedicated root path; apt needs root, uid-1000 can't | |
| Debug interactively (human at terminal) | `dts shell` | `-it` gives full interactive TTY | |
| One-off root inspection (logs, sqlite, config files) | `docker exec -u 0:0 dts-test <cmd>` | Root-only operations outside apt; explicit `docker exec -u 0:0` signals intent | |
| Multi-step stateful commands from a script | `dts exec` with piped stdin | `printf 'cmd1\ncmd2\n' \| dts exec bash` — stdin stays open, runs sequentially | |

**Rule of thumb:** `dts exec` = the test harness path (uid-1000, parity). Raw `docker exec -u 0:0` = the escape hatch for root-only ops that aren't apt installs (e.g. reading sqlite DBs, checking process ports, killing stuck processes). Don't run test commands as root — it masks permission bugs that would fail in CI/Codespace.

## Config

- **Base image**: configurable via `IMAGE`, defaults to `ubuntu:24.04`:
  ```bash
  IMAGE=debian:12 dts up
  IMAGE=node:22 dts up
  ```
- **Container name**: `CONTAINER` (default `dts-test`).
- **Mount target**: always `/src`. Static, predictable.
- **uid/gid**: `CONTAINER_UID`/`CONTAINER_GID` (default 1000).

## The golden rules (each verified by live testing)

1. **Never trust the host.** Always repro in the container. The host has stale packages, leftover venvs, running services — a passing host test proves nothing about a fresh install.
2. **Drive with `docker exec -i`, never `-it`, when scripted.** `-it` fails with "the input device is not a TTY" when stdin is piped (an agent's normal mode). `-i` keeps stdin open, runs scripted AND stateful REPL-style commands fine. Reserve `-it` for a real human typing.
3. **Use `bash -l` (login shell).** Plain `bash -c` is non-interactive and doesn't source `.profile`. Login shell gives host/CI parity.
4. **Run as uid 1000, never root.** CI runner + Codespaces both run uid 1000; root masks permission bugs. `dts` does this automatically.
5. **Install apt packages with `dts apt`, never `dts exec`** — apt (and other package managers) need root, but the container's normal user runs as uid 1000 and can't. Use the dedicated root path:
   ```bash
   dts apt "curl g++ make"          # apt-get update && install -y, as root
   ```
   `dts exec` is the uid-1000 path for the actual test commands. Different targets need different prereqs; keep the tool minimal and make the choice explicit per test.
6. **Verify the mount with md5, not just listing.** Listing can lie; md5 proves same file (host write appears in container, container write appears on host, file md5-identical both sides).
7. **Clean up after yourself.** No orphan containers. `dts clean`.

## Verification is plain shell

There are no `verify` subcommands. Check exit codes, grep output, curl endpoints:

```bash
dts exec "hermes --version" && echo "install OK"
dts exec "curl -sf http://127.0.0.1:20128/healthz && echo server-up"
```

## Non-goals

- No test-definition / YAML schema (target logic = a short bash script).
- No `verify` subcommands.
- No Dockerfile / image build (bind-mount + base image, no rebuild cycle).
- No persistent SSH-like daemon (`docker exec -i` + piped stdin reproduces a stateful session).
- No bundled apt prereqs.

## How to teach/perpetuate this

1. **Never trust the host** — always repro in a fresh container.
2. **Learn the target iteratively** in `shell` mode (or one-off `exec`): poke, observe, confirm, then codify.
3. **Codify as a short bash script** of `dts exec` + checks — repeatable, and arguably CI-run-able.
4. **Record each pitfall** with root cause + fix (as references/ here or a wiki article).

## Pitfalls table (hard-won)

| Pitfall | Root cause | Fix |
|---------|-----------|-----|
| "input device is not a TTY" when scripted | `docker exec -it` needs a host PTY | Use `-i` (no `-t`) when stdin is piped; `-it` only for a real human |
| No `.profile` sourced | `bash -c` is non-interactive | Use `bash -l` (login shell) |
| Permission bugs masked | Tested as root | Always run as uid 1000 (CI/Codespace parity) |
| Mount "works" but file is stale | Bind-mount created once; container cached | Verify with md5 both sides; never trust a listing |
| Orphan containers eat disk | No cleanup | `dts clean` after each session |

## Support files

- `scripts/dts.sh` — the tool itself (up/exec/shell/clean/status).
- `references/dts-usage.md` — worked examples + how the golden rules were validated.

## Related

- Wiki: [docker-test-shell-proposal.md](../../wiki/docker-test-shell-proposal.md) — full design rationale.
- This skill replaces the project-specific `minions-docker-testing` approach with a standalone primitive.
