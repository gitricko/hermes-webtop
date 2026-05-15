#!/bin/bash
source /custom-cont-init.d/common.sh || exit 1

SRC="/custom-cont-init.d/ModelRelay.desktop"

add_model_if_missing() {
    local file="$1"

    if ! jq -e '.model_list | any(.model_name == "modelrelay")' "$file" > /dev/null; then
        echo "[start-2-modelrelay] Adding modelrelay model to $file"
        jq '.model_list += [{
          "model_name": "modelrelay",
          "model": "openai/auto-fastest",
          "api_base": "http://localhost:7352/v1"
        }]' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    fi

    # Set modelrelay as default for agents if not default was set
    if jq -e '.agents.defaults.model_name | select(. == null or . == "")' "$file" > /dev/null; then
        echo "[start-2-modelrelay] Setting modelrelay as defaults for agents in $file"
        jq '.agents |= (. // {}) | .agents.defaults |= (. // {}) | .agents.defaults.model_name = "modelrelay"' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    fi

}

# Prep nodejs npm for ModelRelay 
rm -rf /config/.npm
chown abc:abc -R  /usr/local/lib/node_modules/modelrelay &
chown abc:abc -R  /usr/local/bin/modelrelay &

# Sync desktop file for autostart and desktop icon
sync_desktop_file "$SRC" "/config/.config/autostart/ModelRelay.desktop"
sync_desktop_file "$SRC" "/config/Desktop/ModelRelay.desktop"

# Add modelrelay model to hermes's config as soon as it appears, and set it as default for agents if no default was set
# /config/.hermes/config.json 
(
    for i in {0..60}; do
        if [ -f "/config/.hermes/config.json" ]; then
            add_model_if_missing "/config/.hermes/config.json"
            chown abc:abc "/config/.hermes/config.json"
            break
        fi
        sleep 5
    done
) &
