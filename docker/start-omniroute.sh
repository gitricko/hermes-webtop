#!/bin/bash
source /custom-cont-init.d/common.sh || exit 1

SRC="/custom-cont-init.d/OmniRoute.desktop"

# Sync desktop file for autostart and desktop icon
# sync_desktop_file "$SRC" "/config/.config/autostart/OmniRoute.desktop"
# sync_desktop_file "$SRC" "/config/Desktop/OmniRoute.desktop"

# Prep nodejs npm for OmniRoute 
chown abc:abc -R /usr/local/bin/omniroute

runuser -l abc <<'EOF'
source /custom-cont-init.d/common.sh || exit 1

# Prep nodejs npm for OmniRoute 
sudo rm -rf /config/.npm

# Ensure OmniRoute is owned by abc
ensure_ownership "/usr/local/lib/node_modules/omniroute/app/logs"
ensure_ownership "/usr/local/lib/node_modules/omniroute" &

# Check if OmniRoute should be initialized
[ -f "/config/.omniroute/storage.sqlite" ] && export INIT_OMNIROUTE="0" || export INIT_OMNIROUTE="1"

# Start OmniRoute
echo "[start-omniroute] Starting OmniRoute..."
export REDIS_URL=""
nohup omniroute serve --no-open --log > /tmp/omniroute.log 2>&1 &

if [ "$INIT_OMNIROUTE" -eq "1" ]; then
    echo "[start-omniroute] OmniRoute is fresh. Creating auto-fastest combo..."

    # Wait for OmniRoute to be ready
    while ! curl -s -o /dev/null -w "%{http_code}" http://localhost:20128/v1/models | grep -q "200"; do
        echo "[start-omniroute] Waiting for OmniRoute to be ready..."
        sleep 3
    done

    # Switch OmniRoute to not require login for now, can enable later
    echo "[start-omniroute] Switching OmniRoute to not require login..."
    python3 -c "
    import sqlite3
    conn = sqlite3.connect('/config/.omniroute/storage.sqlite')
    conn.execute('UPDATE key_value SET value = ? WHERE key = ?', ('false', 'requireLogin'))
    conn.commit()
    conn.close()
    "

   # Create auto-fastest combo
    while ! omniroute combo create auto-fastest --strategy auto ; do
        echo "[start-omniroute] omniroute still not ready yet, retrying..."
        sleep 3
    done
    echo "[start-omniroute] OmniRoute Combo auto-fastest created!"

    # Enable OmniRoute MCP if not already enabled
    if omniroute mcp status --json 2>/dev/null | python3 -c "import sys,json;exit(0 if json.load(sys.stdin).get('enabled') else 1)"; then
        echo "[start-omniroute] MCP enabled"
    else
        echo "[start-omniroute] Enabling MCP..."
        curl -s -X PATCH http://localhost:20128/api/settings \
            -H "Content-Type: application/json" -d '{"mcpEnabled":true}' >/dev/null
        echo "[start-omniroute] MCP enabled"
    fi

    # Add omniroute MCP to hermes
    yes Y | hermes mcp add omniroute --command omniroute --args --mcp

    # 2. Get the combo ID (skip the banner line from CLI output)
    COMBO_ID=$(omniroute combo list --json | grep -v "📋" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print([c['id'] for c in d['combos'] if c['name']=='auto-fastest'][0])")

    # 3. Add models + config via API
    curl -s -X PUT "http://localhost:20128/api/combos/$COMBO_ID" \
    -H "Content-Type: application/json" \
    -d '{
        "models": ["oc/deepseek-v4-flash-free", "oc/big-pickle"],
        "strategy": "auto",
        "config": {
        "maxRetries": 2,
        "retryDelayMs": 1000,
        "timeoutMs": 120000,
        "healthCheckEnabled": true
        }
    }'

    echo "[start-omniroute] OmniRoute initialization complete!"
else
    echo "[start-omniroute] OmniRoute is already initialized. Skipping..."
fi

EOF