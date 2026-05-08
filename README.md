# 🪽 Hermes — Web Top
_Run Hermes inside a browser-based Linux desktop with the same project structure as `picoclaw-webtop`, but without preinstalling PicoClaw._

## What this repository is
This repository mirrors the `gitricko/picoclaw-webtop` layout so you can keep the same workflow (`Makefile`, `docker-compose.yml`, `docker/`, `utils-automation/`, CI workflow), while removing PicoClaw from the image.

### Included in the image
- LinuxServer WebTop (Ubuntu MATE)
- Ollama
- ModelRelay
- code-server (port `8888`)

### Not included in the image
- PicoClaw (removed)
- Hermes binary preinstall (you can install Hermes in the running environment using your preferred method)

## Quick start
```bash
make start
```
Then open:
- WebTop: `http://localhost:3000`
- code-server: `http://localhost:8888`

Inside WebTop, use the **Hermes** desktop icon as a terminal launcher and install/run Hermes from there.

## Backup & restore
```bash
make backup
make restore
```
Backups are saved to `backup/hermes_config_backup.tar.gz`.

## Build locally
```bash
make docker-build
make start-locally-baked
```

## License
MIT — see [LICENSE](./LICENSE)
