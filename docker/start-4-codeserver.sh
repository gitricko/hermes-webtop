#!/bin/bash
source /custom-cont-init.d/common.sh || exit 1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SRC="/custom-cont-init.d/CodeServer.desktop"

sync_desktop_file "$SRC" "/config/.config/autostart/CodeServer.desktop"
sync_desktop_file "$SRC" "/config/Desktop/CodeServer.desktop"

chown abc:abc /usr/local/lib/node_modules
chown abc:abc /usr/local/bin

# Add VSCode Extension vscode's config as soon as it appears
(
  for i in {0..999}; do
      if [ -d "/config/.local/share/code-server/User" ]; then
        echo "[start-4-codeserver] code-server configuration found in ~/.local/share/code-server, setting permissions and installing extensions"
        break
      else
        echo "[start-4-codeserver] Force code-server to initialize by calling URI"
        curl -s http://localhost:8888 > /dev/null 2>&1
      fi
      sleep 5
  done

  chown -R abc:abc /config/.local/share/code-server

  EXTENSION=saoudrizwan.claude-dev
  if code --list-extensions | grep -q "${EXTENSION}"; then
    echo "[start-4-codeserver] Extension ${EXTENSION} already installed, skip"
  else
    echo "[start-4-codeserver] Installing Extension ${EXTENSION}..."
    mkdir -p "$HOME/.cline/data"
    cp "${SCRIPT_DIR}/globalState.json" "$HOME/.cline/data/globalState.json"
    cp "${SCRIPT_DIR}/secrets.json" "$HOME/.cline/data/secrets.json"
    runuser -l abc -c "code --install-extension ${EXTENSION}"
    chown -R abc:abc $HOME/.cline/data

  fi

  EXTENSION=joaompfp.hermes-ai-agent
  if code --list-extensions | grep -q "${EXTENSION}"; then
    echo "[start-4-codeserver] Extension ${EXTENSION} already installed, skip"
  else
    echo "[start-4-codeserver] Installing Extension ${EXTENSION}..."
    runuser -l abc -c "curl -sL https://github.com/joaompfp/hermes-vscode/releases/download/v2.0.0/hermes-ai-agent-2.0.0.vsix -o /tmp/hermes-ai-agent.vsix && code --install-extension /tmp/hermes-ai-agent.vsix --force && rm /tmp/hermes-ai-agent.vsix"
  fi

) &