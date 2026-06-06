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
        echo "[common] Error: source file $SRC is missing or not readable." >&2
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
            echo "[common] Updating $DEST (content changed). Preparing replacement"
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
            echo "[common] $DEST is already up to date."
            rm -f "$TMP_DEST"
        fi
    else
        echo "[common] Creating $DEST"
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

# Safely ensures a folder and all its contents are owned by the current running user and group.
# Usage: ensure_ownership <directory_path>
ensure_ownership() {
    local TARGET_DIR="$1"
    
    if [ -z "$TARGET_DIR" ]; then
        echo "[common] Error: Directory path is required for ensure_ownership." >&2
        return 1
    fi
    
    if [ ! -d "$TARGET_DIR" ]; then
        echo "[common] Error: Directory '$TARGET_DIR' does not exist." >&2
        return 1
    fi
    # Dynamically get current user and primary group name
    local CURRENT_USER
    CURRENT_USER=$(id -un)
    local CURRENT_GROUP
    CURRENT_GROUP=$(id -gn)
    # Search for mismatch and fix if needed
    if [ -n "$(find "$TARGET_DIR" \( ! -user "$CURRENT_USER" -o ! -group "$CURRENT_GROUP" \) -print -quit)" ]; then
        echo "[common] Ownership mismatch found in $TARGET_DIR. Correcting to $CURRENT_USER:$CURRENT_GROUP..."
        sudo chown -R "$CURRENT_USER:$CURRENT_GROUP" "$TARGET_DIR"
    else
        echo "[common] Ownership is already correct ($CURRENT_USER:$CURRENT_GROUP) for $TARGET_DIR."
    fi
}