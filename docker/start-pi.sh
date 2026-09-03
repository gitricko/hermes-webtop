#!/bin/bash
source /custom-cont-init.d/common.sh || exit 1

# Ensure Pi is owned by abc (installed globally into /usr/local/lib/node_modules)
ensure_ownership "/usr/local/lib/node_modules/@earendil-works/pi-coding-agent" || true
ensure_ownership "/usr/local/lib/node_modules/pi-coding-agent" || true
ensure_ownership "/usr/local/bin/pi" || true

runuser -l abc <<'EOF'
source /custom-cont-init.d/common.sh || exit 1

PI_DIR="$HOME/.pi/agent"
mkdir -p "$PI_DIR"

# Seed Pi config only on first boot (preserve any user changes on restart).
# Source files are prefixed (pi-*) to avoid colliding with other *.json in /custom-cont-init.d;
# they are renamed to Pi's expected names when copied into ~/.pi/agent/.
if [ ! -f "$PI_DIR/models.json" ]; then
  echo "[start-pi] Seeding Pi models.json (OmniRoute proxy)..."
  cp /custom-cont-init.d/pi-models.json "$PI_DIR/models.json"
  chown abc:abc "$PI_DIR/models.json"
fi

if [ ! -f "$PI_DIR/settings.json" ]; then
  echo "[start-pi] Seeding Pi settings.json (default model omniroute/auto-fastest)..."
  cp /custom-cont-init.d/pi-settings.json "$PI_DIR/settings.json"
  chown abc:abc "$PI_DIR/settings.json"
fi

# Install Pi-agent hermes like fallback extension
echo "[$SCRIPT_NAME] Installing Pi-agent extension..."
pi install git:github.com/gitricko/pi-failover@hermes-impl

echo "[start-pi] Pi agent ready ($(pi --version 2>/dev/null || echo unknown)). Default model: omniroute/auto-fastest"
EOF
