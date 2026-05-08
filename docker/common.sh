#!/bin/bash

# Function to safely sync a desktop file if it has changed
# Usage: sync_desktop_file <source_path> <destination_path>
sync_desktop_file() {
    local SRC="$1"
    local DEST="$2"
    local DEST_DIR
    local DEST_BASE
    local TMP_DEST

    if [ ! -r "$SRC" ]; then
        echo "Error: source file $SRC is missing or not readable." >&2
        return 1
    fi

    DEST_DIR="$(dirname "$DEST")"
    DEST_BASE="$(basename "$DEST")"
    
    # Ensure directory exists and has correct ownership
    mkdir -p "$DEST_DIR"
    chown abc:abc "$DEST_DIR"

    TMP_DEST="$(mktemp "${DEST_DIR}/.${DEST_BASE}.tmp.XXXXXX")" || return 1

    if [ -f "$DEST" ]; then
        # Check if the file content is different
        if ! cmp -s "$SRC" "$DEST"; then
            echo "Updating $DEST (content changed). Preparing replacement"
            if ! cp "$SRC" "$TMP_DEST"; then
                rm -f "$TMP_DEST"
                return 1
            fi
            if ! chown abc:abc "$TMP_DEST"; then
                rm -f "$TMP_DEST"
                return 1
            fi
            # Use a backup just in case, but overwrite it next time
            mv "$DEST" "${DEST}.bak" 2>/dev/null || true
            mv "$TMP_DEST" "$DEST"
        else
            echo "$DEST is already up to date."
            rm -f "$TMP_DEST"
        fi
    else
        echo "Creating $DEST"
        if ! cp "$SRC" "$TMP_DEST"; then
            rm -f "$TMP_DEST"
            return 1
        fi
        if ! chown abc:abc "$TMP_DEST"; then
            rm -f "$TMP_DEST"
            return 1
        fi
        mv "$TMP_DEST" "$DEST"
    fi
}
