#!/bin/bash
source /custom-cont-init.d/common.sh || exit 1

HERDR_CONFIG_DIR="/config/.config/herdr"
HERDR_CONFIG_FILE="$HERDR_CONFIG_DIR/config.toml"

runuser -l abc <<'EOF'
source /custom-cont-init.d/common.sh || exit 1

HERDR_CONFIG_DIR="/config/.config/herdr"
HERDR_CONFIG_FILE="$HERDR_CONFIG_DIR/config.toml"

# Idempotent first-boot seed: never overwrite an existing user config
# (the /config volume is persistent across restarts / image updates).
if [ -f "$HERDR_CONFIG_FILE" ]; then
  echo "[start-herdr] config already present, skipping"
  exit 0
fi

echo "[start-herdr] Seeding herdr config at $HERDR_CONFIG_FILE (first boot)"
mkdir -p "$HERDR_CONFIG_DIR"

cat > "$HERDR_CONFIG_FILE" <<'TOML'
[ui]
show_agent_labels_on_pane_borders = true
# Fix: select-to-copy failing under code-server (web terminal).
# Herdr captures pane mouse input (mouse_capture=true default) and, with the
# default copy_on_select=true, auto-copies each drag/double-click selection to
# the clipboard via OSC 52. In a web terminal (code-server) that OSC 52 write
# does not reliably reach the viewing machine's real clipboard (herdr #2015
# clipboard routing is scoped to VS Code Remote Tunnels, NOT code-server, so
# 0.7.4 here is on the broken path). Setting mouse_capture=false hands the
# mouse back to xterm.js, restoring native select/copy. Trade-off: herdr's
# right-click context menu and click-to-focus pane features are disabled.
mouse_capture = false
TOML

# Validate the TOML parses, but don't fail boot if herdr isn't on PATH yet.
if command -v herdr >/dev/null 2>&1; then
  if herdr config check >/dev/null 2>&1; then
    echo "[start-herdr] herdr config check passed"
  else
    echo "[start-herdr] WARNING: herdr config check reported issues; leaving config in place"
  fi
else
  echo "[start-herdr] herdr binary not on PATH at seed time; skipping config check"
fi

ensure_ownership "$HERDR_CONFIG_DIR"
echo "[start-herdr] herdr config seeded successfully"

EOF
