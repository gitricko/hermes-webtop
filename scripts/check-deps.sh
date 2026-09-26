#!/bin/bash
# Simple dependency version checker for Hermes Webtop
# Checks npm registry for latest versions of key dependencies

set -euo pipefail

echo "=== Hermes Webtop Dependency Check ==="
echo ""

check_npm() {
    local pkg=$1
    local current=$2
    local latest=$(curl -s "https://registry.npmjs.org/$pkg/latest" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('version','?'))" 2>/dev/null)
    if [ "$latest" = "?" ]; then
        echo "  $pkg: current=$current | latest=UNAVAILABLE"
    elif [ "$latest" != "$current" ]; then
        echo "  $pkg: current=$current | latest=$latest [UPDATE AVAILABLE]"
    else
        echo "  $pkg: current=$current | latest=$latest [OK]"
    fi
}

echo "NPM packages:"
check_npm "9router" "0.5.86"
check_npm "omniroute" "3.8.50"
check_npm "@earendil-works/pi-coding-agent" "0.87.1"
check_npm "hermes-agent" "0.21.5"

echo ""
echo "Other (manual check needed):"
echo "  node: 26.10.0"
echo "  ollama: 0.34.1"
echo "  code-server: 4.137.0"
echo "  mnemonic: 0.2.8"
echo "  herdr: 0.7.4"