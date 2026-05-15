#!/bin/bash
source /custom-cont-init.d/common.sh || exit 1

set -e

GLOBAL_STATE="$HOME/.cline/data/globalState.json"
chown abc:abc /usr/local/lib/node_modules
chown abc:abc /usr/local/bin

(
# Wait for file to appear
for i in {0..999}; do
    if [ -f $GLOBAL_STATE ]; then
        echo "[start-2-cline] configuration file $GLOBAL_STATE is found..."
        break
    fi
    sleep 5
done

# Backup existing file
if [ -f "$GLOBAL_STATE" ]; then
    cp "$GLOBAL_STATE" "${GLOBAL_STATE}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "[start-2-cline] Backed up existing globalState.json"
fi

# Create the configuration with jq
jq \
    --arg planModeApiProvider "openai" \
    --arg actModeApiProvider "openai" \
    --arg openAiBaseUrl "http://localhost:7352/v1" \
    --arg planModeOpenAiModelId "auto-fastest" \
    --arg actModeOpenAiModelId "auto-fastest" \
    '
    .planModeApiProvider = $planModeApiProvider |
    .actModeApiProvider = $actModeApiProvider |
    .openAiBaseUrl = $openAiBaseUrl |
    .planModeOpenAiModelId = $planModeOpenAiModelId |
    .actModeOpenAiModelId = $actModeOpenAiModelId |
    .actions = {
        "readFiles": true,
        "readFilesExternally": true,
        "editFiles": true,
        "editFilesExternally": true,
        "executeSafeCommands": true,
        "executeAllCommands": true,
        "useBrowser": true,
        "useMcp": true
    }
    ' "$GLOBAL_STATE" > /tmp/globalState.tmp && mv /tmp/globalState.tmp "$GLOBAL_STATE"

echo "Cline settings updated successfully!"
echo "Configured:"
echo "  - planModeApiProvider: openai"
echo "  - actModeApiProvider: openai"
echo "  - openAiBaseUrl: http://localhost:7352/v1"
echo "  - planModeOpenAiModelId: auto-fastest"
echo "  - actModeOpenAiModelId: auto-fastest"
echo "  - Actions: all enabled (read, edit, execute, browser, mcp)"

)&
