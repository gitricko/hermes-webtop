#!/bin/bash

# Install Cline with default configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[post-create-cmd.sh] Installing Cline with default configuration..."
mkdir -p "$HOME/.cline/data"
cp "${SCRIPT_DIR}/globalState.json" "$HOME/.cline/data/globalState.json"
cp "${SCRIPT_DIR}/secrets.json" "$HOME/.cline/data/secrets.json"
bash -c 'code --force --install-extension saoudrizwan.claude-dev'
npm install -g cline
