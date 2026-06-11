#!/bin/bash
source /custom-cont-init.d/common.sh || exit 1

SRC="/custom-cont-init.d/ModelRelay.desktop"

# Sync desktop file for desktop icon
# sync_desktop_file "$SRC" "/config/Desktop/ModelRelay.desktop"

chown abc:abc -R /usr/local/bin/modelrelay

runuser -l abc <<'EOF'
source /custom-cont-init.d/common.sh || exit 1

# Prep nodejs npm for ModelRelay 
sudo rm -rf /config/.npm

# Ensure ModelRelay is owned by abc
ensure_ownership "/usr/local/lib/node_modules/modelrelay"

# Start ModelRelay
echo "[start-modelrelay] Starting ModelRelay..."
modelrelay --disable
nohup bash -c 'while true; do modelrelay >> /tmp/modelrelay.log 2>&1; sleep 3; done' &
sleep 10

EOF