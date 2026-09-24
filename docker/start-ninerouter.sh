#!/bin/bash
source /custom-cont-init.d/common.sh || exit 1

SRC="/custom-cont-init.d/9Router.desktop"

# Sync desktop file for desktop icon
# sync_desktop_file "$SRC" "/config/Desktop/9Router.desktop"

chown abc:abc -R /usr/local/bin/9router

runuser -l abc <<'EOF'
source /custom-cont-init.d/common.sh || exit 1

# Prep nodejs npm for 9Router 
sudo rm -rf /config/.npm

# Ensure 9Router state dir exists and is writable by abc (fixes EACCES on jwt-secret/model-catalog)
sudo mkdir -p /config/.9router
sudo chown -R abc:abc /config/.9router

# Ensure 9Router is owned by abc
ensure_ownership "/usr/local/lib/node_modules/9router"

# Start 9Router (persistent daemon — no restart loop needed)
echo "[start-ninerouter] Starting 9Router..."
nohup 9router --host 0.0.0.0 --host 127.0.0.1 --log --port 7352 --no-browser --skip-update >> /tmp/9router.log 2>&1 &

# Wait for 9Router to become ready (poll /api/health, up to 300s)
# Same pattern as hermes-codespace post-create-cmd.sh
MAX_ATTEMPTS=300
for ((attempt=1; attempt<=MAX_ATTEMPTS; attempt++)); do
    if curl -s --max-time 3 -o /dev/null http://localhost:7352/api/health; then
        echo "[start-ninerouter] 9Router ready after ${attempt}s"
        break
    fi
    if [ "$attempt" -eq "$MAX_ATTEMPTS" ]; then
        echo "[start-ninerouter] Error: 9Router failed to start after $MAX_ATTEMPTS attempts."
        exit 1
    fi
    sleep 1
done

# Configure 9Router: login (cookie), disable auth, create auto-fastest combo, smoke test
echo "[start-ninerouter] Configuring 9Router..."
bash /usr/local/bin/9router-config >> /tmp/9router-config.log 2>&1
echo "[start-ninerouter] 9Router configuration complete!"

EOF