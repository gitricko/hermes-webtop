#!/bin/bash
# Copy pre-built web UI stamp from image to runtime HERMES_HOME
# This must run synchronously before dashboard starts

STAMP_SRC="/opt/hermes-prebuilt/web-ui-build-stamp.json"
STAMP_DEST="/config/.hermes/web-ui-build-stamp.json"

if [ -f "$STAMP_SRC" ]; then
    echo "[01-copy-web-ui-stamp] Copying pre-built web UI stamp to $STAMP_DEST"
    mkdir -p "$(dirname "$STAMP_DEST")"
    cp -f "$STAMP_SRC" "$STAMP_DEST"
    chown abc:abc "$STAMP_DEST"
else
    echo "[01-copy-web-ui-stamp] WARNING: No pre-built stamp found at $STAMP_SRC"
fi