#!/bin/bash
source /custom-cont-init.d/common.sh || exit 1

SRC="/custom-cont-init.d/CodeServer.desktop"

sync_desktop_file "$SRC" "/config/.config/autostart/CodeServer.desktop"
sync_desktop_file "$SRC" "/config/Desktop/CodeServer.desktop"
