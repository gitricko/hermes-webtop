#!/bin/bash
source /custom-cont-init.d/common.sh || exit 1

SRC="/custom-cont-init.d/Hermes.desktop"

sync_desktop_file "$SRC" "/config/.config/autostart/Hermes.desktop"
sync_desktop_file "$SRC" "/config/Desktop/Hermes.desktop"

chown abc:abc -R /usr/local/lib/hermes-agent &

if [ -d "$HOME/.hermes/sessions" ] && [ -z "$(ls -A "$HOME/.hermes/sessions")" ]; then
  echo "[start-1-hermes.sh] No sessions found in $HOME/.hermes/sessions, setting up default configuration for custom provider"
  hermes config set model.provider custom
  hermes config set model.base_url http://localhost:7352/v1
  hermes config set model.default auto-fastest
fi

chown abc:abc -R  ~/.hermes
