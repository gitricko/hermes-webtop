#!/bin/bash
set -euo pipefail

BASE_URL="http://localhost:7352"
COOKIE_JAR="/tmp/9router-cookie.txt"
rm -f "$COOKIE_JAR"

# 1) login via POST /api/auth/login — 9Router uses HttpOnly cookie (auth_token)
echo "[9router-config] Logging in with password..."
LOGIN_RESPONSE=$(curl -s -c "$COOKIE_JAR" -X POST "$BASE_URL/api/auth/login" -H "Content-Type: application/json" -d '{"password":"123456"}' 2>&1 || echo '{}')
if ! echo "$LOGIN_RESPONSE" | jq -e '.success // empty' >/dev/null 2>&1; then
    echo "[9router-config] WARNING: login body: $LOGIN_RESPONSE"
fi
if [ ! -f "$COOKIE_JAR" ] || ! grep -q "auth_token" "$COOKIE_JAR" 2>/dev/null; then
    echo "[9router-config] WARNING: no auth_token cookie set — login may have failed"
else
    echo "[9router-config] Login successful (auth cookie set)"
fi

# Cookie-based auth for all subsequent requests
AUTH_ARGS=("-b" "$COOKIE_JAR")

# 2) disable requireLogin and requireApiKey via PATCH /api/settings
echo "[9router-config] Disabling requireLogin and requireApiKey..."
curl -s -X PATCH "$BASE_URL/api/settings" -H "Content-Type: application/json" "${AUTH_ARGS[@]}" -d '{"requireLogin":false,"requireApiKey":false}' > /dev/null
echo "[9router-config] Settings updated: requireLogin=false, requireApiKey=false"

# 3) delete existing auto-fastest combo if present
echo "[9router-config] Deleting existing auto-fastest combo if present..."
curl -s -X DELETE "$BASE_URL/api/combos/auto-fastest" \
    -H "Content-Type: application/json" \
    "${AUTH_ARGS[@]}" > /dev/null || true
echo "[9router-config] Existing combo deleted (or did not exist)"

# 4) create new auto-fastest combo with 8 free oc/ models
echo "[9router-config] Creating new auto-fastest combo with 8 free oc/ models..."

MODELS='["oc/muse-spark-1.2","oc/muse-spark-1.3","oc/union-alpha","oc/big-pickle","oc/mimo-v2.5-free","oc/ling-3.0-flash-fin-free","oc/nemotron-3-ultra-free","oc/nemotron-3.5-lightning-free"]'

CREATE_RESPONSE=$(curl -s -X POST "$BASE_URL/api/combos" -H "Content-Type: application/json" "${AUTH_ARGS[@]}" -d "{\"name\":\"auto-fastest\",\"models\":$MODELS}")

echo "$CREATE_RESPONSE" | jq -e '.name // empty' > /dev/null || {
    echo "[9router-config] Error: Failed to create combo"
    echo "[9router-config] Response: $CREATE_RESPONSE"
    exit 1
}
echo "[9router-config] Combo auto-fastest created successfully"

# 5) set round-robin fallback strategy
# 6) PATCH settings with comboStrategies
echo "[9router-config] Setting round-robin fallback strategy via comboStrategies..."
curl -s -X PATCH "$BASE_URL/api/settings" \
    -H "Content-Type: application/json" \
    "${AUTH_ARGS[@]}" \
    -d '{"comboStrategies":{"fallback":"round-robin"}}' > /dev/null
echo "[9router-config] comboStrategies.fallback set to round-robin"

# 7) smoke test via /v1/chat/completions
echo "[9router-config] Running smoke test via /v1/chat/completions..."
SMOKE_RESPONSE=$(curl -s -X POST "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    "${AUTH_ARGS[@]}" \
    -d '{"model":"auto-fastest","messages":[{"role":"user","content":"hello"}]}')

SMOKE_CONTENT=$(echo "$SMOKE_RESPONSE" | jq -r '.choices[0].message.content // empty')

if [ -n "$SMOKE_CONTENT" ]; then
    echo "[9router-config] Smoke test PASSED - received response from model"
    echo "[9router-config] Response preview: ${SMOKE_CONTENT:0:100}"
else
    echo "[9router-config] Smoke test FAILED - no content in response"
    echo "[9router-config] Response: $SMOKE_RESPONSE"
    exit 1
fi

echo "[9router-config] 9Router configuration complete!"