# dts usage & validation notes

## Worked examples

Test a `./install.sh` in a fresh container (e.g. `.minions` or any installer):

```bash
cd /workspaces/your-repo
/path/to/dts.sh up
dts exec "bash /src/install.sh"
# if it needs apt packages, install one-off (as root):
dts apt "curl g++ make"
dts exec "./src/bin/my-tool --version"
# plain-shell verification:
dts exec "my-tool --version" && echo "install OK"
dts clean
```

Use a different base image:
```bash
IMAGE=debian:12 dts up
IMAGE=node:22 dts up
```

Interactive debugging (a human, has a terminal):
```bash
dts shell
```

## How the golden rules were validated (live)

These were verified empirically in a real `ubuntu:24.04` container:

1. **Host state lies** — the Codespace already has Node, a venv, hermes, stale configs, and running services; a host test passes while the fresh install fails. Repro inside the container instead.
2. **TTY** — `docker exec -it` fails with "the input device is not a TTY" when stdin is piped (an agent's normal mode); `docker exec -i` (no `-t`) runs both scripted one-shots AND stateful REPL-style piped input (`printf 'x=2\necho $((x*21))\nexit\n' | docker exec -i ...` -> 42).
3. **Login shell** — `bash -c` is non-interactive and doesn't source `.profile` (PATH etc.); `bash -l` sources it, matching CI.
4. **uid 1000** — CI runner and Codespace both run uid 1000; root masks permission errors that break the real install. `dts exec` runs as uid 1000.
5. **Root-only ops** — package managers (apt) need root; uid-1000 user can't run them. Use the dedicated `dts apt` root path for installs.
6. **Mount** — verified bidirectional: a file written on the host appears in the container and vice-versa; `md5sum` identical both sides (not just a listing).
7. **Cleanup** — orphan containers hold disk; always `dts clean`.

## Pitfalls & conventions map

| Topic | Convention |
|-------|-----------|
| Scripted exec | `-i`, never `-it` |
| Human shell | `-it` |
| User | uid 1000 (ubuntu in Ubuntu/Debian) |
| Mount | always `/src` |
| Base image | `IMAGE` env, default `ubuntu:24.04` |
| apt prereqs | manual one-off via `dts apt`, not bundled |
| Verification | plain shell (exit code, grep, curl) |

## Long-running installs/boots: run detached (`nohup`) so they don't get SIGTERM'd

A multi-minute `install.sh`/`boot.sh` run as a plain foreground `dts exec` can be killed (exit 143 / "Terminated") when the driving exec session ends, and `pkill -f install.sh` on the host matches your own exec command line (it contains "install.sh") and kills your own pipeline.

**Detach the long part** and write to a log, then poll with short separate `dts exec` calls:

```bash
dts exec 'nohup bash -c "bash /src/install.sh > /home/ubuntu/install.log 2>&1; \
  echo INSTALL_EXIT=$? >> /home/ubuntu/install.log; \
  bash -l /home/ubuntu/.minions/boot.sh >> /home/ubuntu/boot.log 2>&1; \
  echo BOOT_EXIT=$? >> /home/ubuntu/boot.log" >/dev/null 2>&1 & echo launched'

sleep 120
dts exec 'grep -E "installed and verified|INSTALL_EXIT|Terminated|Killed" /home/ubuntu/install.log | tail -5'
dts exec 'tail -5 /home/ubuntu/boot.log; grep BOOT_EXIT /home/ubuntu/boot.log'
```

Rules: wrap in `nohup bash -c '...' &`, log to a file not stdout, kill by exact PID never `pkill -f '<scriptname>'`.

## Root vs uid-1000: when to use which

| Operation | Command | User | Note |
|-----------|---------|------|------|
| Test/build commands | `dts exec "..."` | uid-1000 | Default path — CI parity |
| apt install | `dts apt "pkg1 pkg2"` | root | Dedicated root path |
| Read sqlite DB | `docker exec -u 0:0 dts-test cat ...` | root | Root-only inspection |
| Check process ports | `docker exec -u 0:0 dts-test ss -tlnp` | root | Root-only |
| Kill stuck process | `docker exec -u 0:0 dts-test pkill ...` | root | Root-only |
| Interactive debug | `dts shell` | uid-1000 | Human, `-it` |
| Piped multi-step | `printf '...' | dts exec bash` | uid-1000 | Agent/script |

**Key point:** Test commands always run as uid-1000. Root (`docker exec -u 0:0`) is an explicit escape hatch for ops that genuinely require it — never for the actual test logic, because running as root masks permission bugs that would fail in CI/Codespace.
