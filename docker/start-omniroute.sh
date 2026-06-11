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

# Start OmniRoute
echo "[start-omniroute] Starting OmniRoute..."
nohup omniroute --no-open >> /tmp/omniroute.log 2>&1 &
sleep 10

EOF