#!/bin/bash
source /custom-cont-init.d/common.sh || exit 1

SRC="/custom-cont-init.d/Hermes.desktop"

# sync_desktop_file "$SRC" "/config/.config/autostart/Hermes.desktop"
# sync_desktop_file "$SRC" "/config/Desktop/Hermes.desktop"

(

# Fast change ownership of hermes-agent root directory to abc user to avoid permission issues
shopt -s dotglob
chown abc:abc /usr/local/lib/hermes-agent/*
shopt -u dotglob

runuser -l abc <<'EOF'
  source /custom-cont-init.d/common.sh || exit 1
  ensure_ownership "$HOME/.hermes"
  ensure_ownership "/usr/local/lib/hermes-agent" &

  if [ -d "$HOME/.hermes/logs" ] && [ -z "$(ls -A "$HOME/.hermes/logs")" ]; then
    echo "[start-hermes] No logs found in $HOME/.hermes/logs, setting up default configuration for custom provider"
    echo "[start-hermes] Initializing hermes config..."
    hermes config set model.default auto-fastest
    hermes config set model.provider omniroute
    hermes config set providers.omniroute.base_url http://localhost:20128/v1
    hermes config set providers.omniroute.api_key no-key-needed
    hermes config set providers.modelrelay.base_url http://localhost:7352/v1
    hermes config set providers.modelrelay.api_key no-key-needed
    hermes config set fallback_providers.provider modelrelay
    hermes config set fallback_providers.model auto-fastest
  
    # Turn off approval alert and live dangerously since u are in a self-contained container.
    hermes config set approvals.mode off
    # Turn on memory by default and to mnemon
    hermes config set memory.memory_enabled true
    hermes config set memory.user_profile_enabled true
    hermes config set memory.provider mnemon
    # optimize for kanban
    hermes config set agent.max_turns 120
    hermes config set kanban.failure_limit 3

  fi

  mkdir -p  ~/.hermes/logs

  # Install Telegram gateway dependency if missing
  ensure_ownership "/usr/local/lib/hermes-agent/venv"
  /usr/local/lib/hermes-agent/venv/bin/python -m ensurepip --upgrade || true
  ln -s /usr/local/lib/hermes-agent/venv/bin/pip3 /usr/local/lib/hermes-agent/venv/bin/pip || true
  /usr/local/lib/hermes-agent/venv/bin/pip install python-telegram-bot 2>/dev/null || true

  # update mnemon provider if version changes (synced BEFORE gateway starts)
  echo "[start-hermes] Checking mnemon provider..."
  rm -rf /tmp/mnemon_repo
  if git clone https://github.com/gitricko/hermes-plugin-mnemon /tmp/mnemon_repo; then
    if [ ! -d "$HOME/.hermes/plugins/mnemon" ] || ! diff -r -q -x __pycache__ "$HOME/.hermes/plugins/mnemon" "/tmp/mnemon_repo/mnemon" >/dev/null 2>&1; then
      echo "[start-hermes] Mnemon plugin is missing or out of date. Updating..."
      mkdir -p "$HOME/.hermes/plugins"
      rm -rf "$HOME/.hermes/plugins/mnemon"
      cp -r "/tmp/mnemon_repo/mnemon" "$HOME/.hermes/plugins/mnemon"
      echo "[start-hermes] Mnemon plugin updated successfully."
    else
      echo "[start-hermes] Mnemon plugin is up to date."
    fi
    rm -rf /tmp/mnemon_repo
  else
    echo "[start-hermes] WARNING: Failed to clone gitricko/hermes-plugin-mnemon repository."
  fi

  # Start Hermes Gateway in background (mnemon is ready before this fires)
  echo "[start-hermes] Starting Hermes Gateway..."
  nohup hermes gateway run --no-supervise > ~/.hermes/logs/gateway.log 2>&1 &

  # Start Hermes Dashboard in background
  ensure_ownership "/usr/local/lib/hermes-agent/hermes_cli"
  ensure_ownership "/usr/local/lib/hermes-agent/web"
  echo "[start-hermes] Starting Hermes Dashboard..."
  nohup hermes dashboard --host 0.0.0.0 --insecure --no-open > ~/.hermes/logs/dashboard.log 2>&1 &

  # Remind Hermes on Mnemon setup if needed
  if [ ! -f "$HOME/.hermes/memories/USER.md" ]; then
    echo "[start-hermes] Setting up Mnemon USER.md..."
    echo 'Always use Mnemon (mnemon_remember / mnemon_recall) as primary memory provider instead of the standard memory() tool. Mnemon has no char limit. Only fall back to memory() for structured preference data (target=user or memory).' > "$HOME/.hermes/memories/USER.md"
  fi

  echo "[start-hermes] all hermes-agent services started and ready."

EOF

) &

# Wait for Hermes dashboard to be ready (replaces brittle sleep 15)
echo "[start-hermes] Waiting for Hermes dashboard to become healthy..."
for i in $(seq 1 20); do
  if curl -s -o /dev/null -w "%{http_code}" http://localhost:9119 2>/dev/null | grep -q "200\|302\|401"; then
    echo "[start-hermes] Dashboard ready after $((i * 3)) seconds."
    break
  fi
  if [ "$i" -eq 20 ]; then
    echo "[start-hermes] WARNING: Dashboard did not respond within 60 seconds. Check ~/.hermes/logs/dashboard.log"
  fi
  sleep 3
done

# Run boot-time health self-check after all services are ready
echo "[start-hermes] Running boot-time health self-check..."
/usr/local/bin/self-check || echo "[start-hermes] WARNING: self-check reported issues"

# Wait for background hermes services to naturally complete (handled by the & above)
wait