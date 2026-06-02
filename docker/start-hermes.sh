#!/bin/bash
source /custom-cont-init.d/common.sh || exit 1

SRC="/custom-cont-init.d/Hermes.desktop"

chown abc:abc -R /usr/local/lib/hermes-agent/web
chown abc:abc -R /usr/local/lib/hermes-agent &

# sync_desktop_file "$SRC" "/config/.config/autostart/Hermes.desktop"
# sync_desktop_file "$SRC" "/config/Desktop/Hermes.desktop"

chown abc:abc -R  ~/.hermes

runuser -l abc <<'EOF'
  if [ -d "$HOME/.hermes/logs" ] && [ -z "$(ls -A "$HOME/.hermes/logs")" ]; then
    echo "[start-hermes] No logs found in $HOME/.hermes/logs, setting up default configuration for custom provider"
    echo "[start-hermes] Initializing hermes config..."
    hermes config set model.provider custom
    hermes config set model.base_url http://localhost:7352/v1
    hermes config set model.default auto-fastest
    # Turn off approval alert and live dangerously since u are in a self-contained container.
    hermes config set approvals.mode off
    # Turn on memory by default and to mnemon
    hermes config set memory.memory_enabled true
    hermes config set memory.user_profile_enabled true
    hermes config set memory.provider mnemon
  fi

  # Start Hermes Gateway in background
  echo "[start-hermes] Starting Hermes Gateway..."
  mkdir -p  ~/.hermes/logs
  nohup hermes gateway run --no-supervise > ~/.hermes/logs/gateway.log 2>&1 &

  # Start Hermes Dashboard in background
  echo "[start-hermes] Starting Hermes Dashboard..."
  nohup hermes dashboard --host 0.0.0.0 --insecure --no-open > ~/.hermes/logs/dashboard.log 2>&1 &

  # update mnemon provider if version changes
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

EOF

chown abc:abc -R  ~/.hermes
