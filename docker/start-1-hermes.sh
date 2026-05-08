#!/bin/bash
source /custom-cont-init.d/common.sh || exit 1

SRC="/custom-cont-init.d/Hermes.desktop"

sync_desktop_file "$SRC" "/config/.config/autostart/Hermes.desktop"
sync_desktop_file "$SRC" "/config/Desktop/Hermes.desktop"
