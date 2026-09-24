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

# Ensure 9Router is owned by abc
ensure_ownership "/usr/local/lib/node_modules/9router"

# Start 9Router
echo "[start-ninerouter] Starting 9Router..."
nohup bash -c 'while true; do 9router --host 0.0.0.0 --host 127.0.0.1 --port 7352 --no-browser --skip-update >> /tmp/9router.log 2>&1; sleep 3; done' &
sleep 10

# Configure 9Router: login, disable auth, create auto-fastest combo, smoke test
bash /usr/local/bin/9router-config >> /tmp/9router-config.log 2>&1

EOF