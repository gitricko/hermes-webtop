#!/bin/bash
source /custom-cont-init.d/common.sh || exit 1

SRC="/custom-cont-init.d/CodeServer.desktop"

sync_desktop_file "$SRC" "/config/.config/autostart/CodeServer.desktop"
sync_desktop_file "$SRC" "/config/Desktop/CodeServer.desktop"

EXTENSION=saoudrizwan.claude-dev
if code --list-extensions | grep -q "${EXTENSION}"; then
  echo "Extension ${EXTENSION} already installed, skip"
else
  echo "Installing Extension ${EXTENSION}..."
  code --install-extension ${EXTENSION}
fi

EXTENSION=joaompfp.hermes-ai-agent
if code --list-extensions | grep -q "${EXTENSION}"; then
  echo "Extension ${EXTENSION} already installed, skip"
else
  echo "Installing Extension ${EXTENSION}..."
    curl -sL https://github.com/joaompfp/hermes-vscode/releases/download/v2.0.0/hermes-ai-agent-2.0.0.vsix -o /tmp/hermes-ai-agent.vsix && code-server --install-extension /tmp/hermes-ai-agent.vsix --force && rm /tmp/hermes-ai-agent.vsix
fi


