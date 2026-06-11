#!/bin/bash
source /custom-cont-init.d/common.sh || exit 1
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# SRC="/custom-cont-init.d/CodeServer.desktop"

# sync_desktop_file "$SRC" "/config/.config/autostart/CodeServer.desktop"
# sync_desktop_file "$SRC" "/config/Desktop/CodeServer.desktop"

chown -R abc:abc /custom-cont-init.d
chown abc:abc /usr/local/lib/node_modules
chown abc:abc /usr/local/bin
chown -R abc:abc /config/.local

runuser -l abc <<'EOF'
source /custom-cont-init.d/common.sh || exit 1

# Start Code-Server in the background
nohup bash -c 'code-server --trusted-origins=* --auth none --bind-addr 0.0.0.0:8888' > /tmp/codeserver.log 2>&1 &

# Add VSCode Extension vscode's config as soon as it appears
(
  for i in {0..999}; do
      if [ -d "/config/.local/share/code-server/User" ]; then
        echo "[start-codeserver] code-server configuration found in ~/.local/share/code-server, setting permissions and installing extensions"
        break
      else
        echo "[start-codeserver] Force code-server to initialize by calling URI"
        curl -s http://localhost:8888 > /dev/null 2>&1
      fi
      sleep 5
  done

  EXTENSION=hermes-code-agent
  VERSION=3.0.3
  if code --list-extensions | grep -q "${EXTENSION}"; then
    echo "[start-codeserver] Extension ${EXTENSION} already installed, skip"
  else
    echo "[start-codeserver] Installing Extension ${EXTENSION}..."
    curl -sL https://github.com/gitricko/hermes-vscode/releases/download/v${VERSION}/${EXTENSION}-${VERSION}.vsix -o /tmp/${EXTENSION}.vsix && code --install-extension /tmp/${EXTENSION}.vsix --force && rm /tmp/${EXTENSION}.vsix
  fi

  EXTENSION=saoudrizwan.claude-dev
  if code --list-extensions | grep -q "${EXTENSION}"; then
    echo "[start-codeserver] Extension ${EXTENSION} already installed, skip"
  else
    echo "[start-codeserver] Installing Extension ${EXTENSION}..."
    mkdir -p "$HOME/.cline/data"
    cp "/custom-cont-init.d/globalState.json" "$HOME/.cline/data/globalState.json"
    cp "/custom-cont-init.d/secrets.json" "$HOME/.cline/data/secrets.json"
    code --install-extension ${EXTENSION}
  fi

  EXTENSION=anthropic.claude-code
  if code --list-extensions | grep -q "${EXTENSION}"; then
    echo "[start-codeserver] Extension ${EXTENSION} already installed, skip"
  else
    echo "[start-codeserver] Installing Extension ${EXTENSION} + claude-cli..."
    mkdir -p $HOME/.claude
    cp /custom-cont-init.d/claude-term-settings.json $HOME/.claude/settings.json
    curl -fsSL https://claude.ai/install.sh | bash
    mkdir -p $HOME/.local/share/code-server/User
    cp /custom-cont-init.d/claude-vscode-settings.json $HOME/.local/share/code-server/User/settings.json
    cp /custom-cont-init.d/.claude.json $HOME/.claude.json
    cp /custom-cont-init.d/CLAUDE.md $HOME/.claude/CLAUDE.md
    code --install-extension ${EXTENSION}

    # integrate mnemon into claude-code
    mnemon setup --yes --global  --target claude-code
  fi

) &

EOF
