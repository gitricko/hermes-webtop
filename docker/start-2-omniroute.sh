#!/bin/bash
source /custom-cont-init.d/common.sh || exit 1

SRC="/custom-cont-init.d/OmniRoute.desktop"

# Prep nodejs npm for OmniRoute 
rm -rf /config/.npm
chown abc:abc -R  /usr/local/lib/node_modules &
chown abc:abc -R  /usr/local/bin &

# Sync desktop file for autostart and desktop icon
sync_desktop_file "$SRC" "/config/.config/autostart/OmniRoute.desktop"
sync_desktop_file "$SRC" "/config/Desktop/OmniRoute.desktop"