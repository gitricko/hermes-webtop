#!/bin/bash
# self-check.sh — Hermes-WebTop boot-time health diagnostics
#
# Probes all components of the hermes-webtop stack and produces a
# human-readable health report + machine-parseable JSON summary.
#
# Auto-discovers Telegram delivery from Hermes config.yaml — no
# separate env vars needed. Falls back to stdout-only if Telegram
# is not configured (the Codespaces / first-time-user default).
#
# Behavioural env vars (thresholds only):
#   HERMES_WEBTOP_SKIP_CHECKS     — comma-separated check names to skip
#   HERMES_WEBTOP_DISK_WARN_PCT   — disk % threshold for warning (default: 85)
#   HERMES_WEBTOP_CRITICAL_SERVICES— ports whose failure → exit 2 (default: all 4)
#
# Exit codes:
#   0  — all checks passed (or only warnings)
#   1  — one or more warnings (disk, cron, etc.)
#   2  — one or more critical failures (service down, config broken)

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
SKIP_CHECKS="${HERMES_WEBTOP_SKIP_CHECKS:-}"
DISK_WARN_PCT="${HERMES_WEBTOP_DISK_WARN_PCT:-85}"
CRITICAL_SERVICES="${HERMES_WEBTOP_CRITICAL_SERVICES:-3000 8888 7352 20128}"

HERMES_CONFIG="${HERMES_CONFIG:-$HOME/.hermes/config.yaml}"
HERMES_GATEWAY_URL="${HERMES_GATEWAY_URL:-http://localhost:9119}"
REPORT_FILE="/tmp/health-report.json"

# Colours (disabled if stderr is not a terminal, e.g. CI)
if [ -t 2 ]; then
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  RED='\033[0;31m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; BOLD=''; NC=''
fi

# ── State ────────────────────────────────────────────────────────────────────
CRITICAL=0
WARNINGS=0
JSON_RESULTS='[]'  # JSON array (accumulating)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Helpers ──────────────────────────────────────────────────────────────────
_ok()   { local label="$1" msg="$2"; printf "  ${GREEN}✅${NC} %-18s %s\n" "$label" "$msg"; }
_warn() { local label="$1" msg="$2"; printf "  ${YELLOW}⚠️ ${NC}%-18s %s\n" "$label" "$msg"; ((WARNINGS++)) || true; }
_fail() { local label="$1" msg="$2"; printf "  ${RED}❌${NC} %-18s %s\n" "$label" "$msg"; ((CRITICAL++)) || true; }

json_add() {
  # json_add <name> <status: ok|warn|fail> <message> [detail_json]
  local name="$1" status="$2" message="$3" detail="${4:-null}"
  JSON_RESULTS=$(echo "$JSON_RESULTS" | python3 -c "
import json,sys
results = json.loads(sys.stdin.read())
results.append({
  'name': '$name',
  'status': '$status',
  'message': '$(echo "$message" | sed "s/'/\\\\'/g")',
  'detail': $detail
})
print(json.dumps(results))
")
}

should_skip() {
  local name="$1"
  [ -z "$SKIP_CHECKS" ] && return 1  # don't skip
  for s in $(echo "$SKIP_CHECKS" | tr ',' ' '); do
    [ "$s" = "$name" ] && return 0
  done
  return 1
}

section() {
  echo ""
  echo " ${BOLD}$1${NC}"
  echo " ───────────────────────────────────────────────"
}

# ── Checks ───────────────────────────────────────────────────────────────────

echo ""
echo " ════════════════════════════════════════════════════════════"
echo "  ${BOLD}HERMES-WEBTOP HEALTH REPORT${NC}"
echo "  $(date -u)"
echo " ════════════════════════════════════════════════════════════"

# ── 1. Services ──────────────────────────────────────────────────────────────
section "Services"

if ! should_skip "services"; then
  # Poll all service ports until all respond or timeout
  PORT_POLL_TIMEOUT=120
  POLL_STARTED_AT=$(date +%s)
  declare -A RESPONDED=([3000]="" [8888]="" [7352]="" [20128]="", [9119]="")

  while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - POLL_STARTED_AT))

    # Collecting responses
    if [ "$ELAPSED" -gt "$PORT_POLL_TIMEOUT" ]; then
      for pair in "3000:WebTop" "8888:CodeServer" "7352:ModelRelay" "20128:OmniRoute", "9119:HermesGateway"; do
        PORT="${pair%%:*}"
        NAME="${pair##*:}"
        if [ "${RESPONDED[$PORT]}" != "true" ]; then
          echo "  $NAME (:$PORT) — ❌ never responded"
        fi
      done
      break
    fi

    # Testing ports
    for pair in "3000:WebTop" "8888:CodeServer" "7352:ModelRelay" "20128:OmniRoute" "9119:HermesGateway"; do
      PORT="${pair%%:*}"
      NAME="${pair##*:}"

      if [ "${RESPONDED[$PORT]}" = "true" ]; then
        continue
      fi

      HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:${PORT}" 2>/dev/null || HTTP_CODE="000")
      HTTP_CODE=$(echo "$HTTP_CODE" | tr -d '[:space:]')

      if [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
        echo "  $NAME (:$PORT) — ✅ HTTP ${HTTP_CODE} (${ELAPSED}s)"
        RESPONDED[$PORT]="true"
      fi
    done

    # Check if all ports responded
    ALL_RESPONDED=true
    for port in 3000 8888 7352 20128 9119; do
      if [ "${RESPONDED[$port]}" != "true" ]; then
        ALL_RESPONDED=false
        break
      fi
    done

    if [ "$ALL_RESPONDED" = "true" ]; then
      break
    fi

    sleep 5
  done

  if [ "$ALL_RESPONDED" = "true" ]; then
    echo ""
    _ok "Services Ports" "responding within ${ELAPSED}s"
  else
    echo ""
    _fail "Services Ports" "failed to respond within ${PORT_POLL_TIMEOUT}s"
  fi

else
  echo "   (skipped)"
fi

# ── 2. Models ────────────────────────────────────────────────────────────────
section "Models"

if ! should_skip "models"; then
  models_json=$(curl -s --max-time 5 "http://localhost:20128/v1/models" 2>/dev/null || echo '{}')
  model_count=$(echo "$models_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('data',[])))" 2>/dev/null || echo "0")
  # Try to get the default combo name from Hermes config
  default_model=$(grep -A1 '^model:' "$HERMES_CONFIG" 2>/dev/null | grep 'default' | head -1 | sed 's/.*default: *//' || echo "unknown")
  default_model="${default_model:-unknown}"

  if [ "$model_count" -gt 0 ] 2>/dev/null; then
    _ok "OmniRoute" "${model_count} models available (default: ${default_model})"
    json_add "models" "ok" "${model_count} models, default combo: ${default_model}" "{\"count\":${model_count},\"default\":\"${default_model}\"}"
  else
    _warn "OmniRoute" "no models returned from /v1/models (may still be starting)"
    json_add "models" "warn" "no models returned (may still be booting)" "{\"count\":0}"
  fi
else
  echo "   (skipped)"
fi

# ── 3. Mnemon ────────────────────────────────────────────────────────────────
section "Mnemon"

if ! should_skip "mnemon"; then
  mnemon_version=$(mnemon --version 2>/dev/null || echo "not-found")
  mnemon_db=$(find "$HOME" -maxdepth 3 -name ".mnemon" -type d 2>/dev/null | head -1) || true

  if [ "$mnemon_version" != "not-found" ]; then
    _ok "Binary" "${mnemon_version}"
    json_add "mnemon:binary" "ok" "mnemon ${mnemon_version}" "{\"version\":\"${mnemon_version}\"}"
  else
    _fail "Binary" "mnemon not found in PATH"
    json_add "mnemon:binary" "fail" "mnemon binary not found" "{}"
  fi

  if [ -n "$mnemon_db" ]; then
    _ok "Database" "found at ${mnemon_db}"
    json_add "mnemon:db" "ok" "mnemon db at ${mnemon_db}" "{\"path\":\"${mnemon_db}\"}"
  else
    _warn "Database" "no .mnemon directory found (will be created on first use)"
    json_add "mnemon:db" "warn" "no .mnemon directory yet" "{}"
  fi
else
  echo "   (skipped)"
fi

# ── 4. Hermes config ─────────────────────────────────────────────────────────
section "Hermes"

if ! should_skip "hermes"; then
  if [ -f "$HERMES_CONFIG" ]; then
    cfg_model=$(grep -A1 '^model:' "$HERMES_CONFIG" 2>/dev/null | grep 'default' | head -1 | sed 's/.*default: *//' || echo "")
    cfg_provider=$(grep -A1 '^model:' "$HERMES_CONFIG" 2>/dev/null | grep 'provider' | head -1 | sed 's/.*provider: *//' || echo "")
    has_gateway=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$HERMES_GATEWAY_URL" 2>/dev/null || true)
    has_gateway="${has_gateway:-000}"

    if [ -n "$cfg_model" ]; then
      _ok "Config" "model=${cfg_model}, provider=${cfg_provider:-unset}"
      json_add "hermes:config" "ok" "config valid: model=$cfg_model, provider=$cfg_provider" "{\"model\":\"${cfg_model}\",\"provider\":\"${cfg_provider}\"}"
    else
      _warn "Config" "model not set in config (may be fresh install)"
      json_add "hermes:config" "warn" "model not configured" "{}"
    fi

    if [ "$has_gateway" != "000" ]; then
      _ok "Gateway" "HTTP ${has_gateway} at ${HERMES_GATEWAY_URL}"
      json_add "hermes:gateway" "ok" "gateway responded HTTP ${has_gateway}" "{\"http_code\":${has_gateway}}"
    else
      _fail "Gateway" "no response from ${HERMES_GATEWAY_URL}"
      json_add "hermes:gateway" "fail" "gateway unreachable" "{}"
    fi
  else
    _warn "Config" "no config at ${HERMES_CONFIG} (may still be initializing)"
    json_add "hermes:config" "warn" "hermes config file not found (runtime)" "{}"
  fi
else
  echo "   (skipped)"
fi

# ── 5. Disk ──────────────────────────────────────────────────────────────────
section "Disk"

if ! should_skip "disk"; then
  disk_raw=$(df /config 2>/dev/null | tail -1 || true)
  if [ -n "$disk_raw" ]; then
    disk_pct=$(echo "$disk_raw" | awk '{print $5}' | tr -d '%')
    disk_avail=$(echo "$disk_raw" | awk '{print $4}')
    # Convert to human-readable if block size is 1K
    if [[ "$disk_avail" =~ ^[0-9]+$ ]]; then
      disk_avail_gb=$(( disk_avail / 1024 / 1024 ))
      disk_total_gb=$(( $(echo "$disk_raw" | awk '{print $2}') / 1024 / 1024 ))
    else
      disk_avail_gb="$disk_avail"
      disk_total_gb="?"
    fi

    if [ "$disk_pct" -ge 95 ] 2>/dev/null; then
      _fail "Usage" "${disk_pct}% used (${disk_avail_gb}G available) — CRITICAL"
      json_add "disk" "fail" "${disk_pct}% used, ${disk_avail_gb}G free" "{\"used_pct\":${disk_pct},\"available_gb\":${disk_avail_gb}}"
    elif [ "$disk_pct" -ge "$DISK_WARN_PCT" ] 2>/dev/null; then
      _warn "Usage" "${disk_pct}% used (${disk_avail_gb}G available) — threshold: ${DISK_WARN_PCT}%"
      json_add "disk" "warn" "${disk_pct}% used, ${disk_avail_gb}G free" "{\"used_pct\":${disk_pct},\"available_gb\":${disk_avail_gb},\"threshold\":${DISK_WARN_PCT}}"
    else
      _ok "Usage" "${disk_pct}% used (${disk_avail_gb}G available)"
      json_add "disk" "ok" "${disk_pct}% used, ${disk_avail_gb}G free" "{\"used_pct\":${disk_pct},\"available_gb\":${disk_avail_gb}}"
    fi
  else
    _warn "Usage" "could not read disk stats for /config"
    json_add "disk" "warn" "df failed" "{}"
  fi
else
  echo "   (skipped)"
fi

# ── 6. Memory ────────────────────────────────────────────────────────────────
section "Memory"

if ! should_skip "memory"; then
  mem_raw=$(free -m 2>/dev/null | grep "^Mem:" || true)
  if [ -n "$mem_raw" ]; then
    mem_total=$(echo "$mem_raw" | awk '{print $2}')
    mem_used=$(echo "$mem_raw" | awk '{print $3}')
    mem_pct=$(( mem_used * 100 / mem_total ))

    if [ "$mem_pct" -ge 90 ] 2>/dev/null; then
      _warn "Usage" "${mem_pct}% used (${mem_used}M / ${mem_total}M)"
      json_add "memory" "warn" "${mem_pct}% used" "{\"used_pct\":${mem_pct},\"used_mb\":${mem_used},\"total_mb\":${mem_total}}"
    else
      _ok "Usage" "${mem_pct}% used (${mem_used}M / ${mem_total}M)"
      json_add "memory" "ok" "${mem_pct}% used" "{\"used_pct\":${mem_pct},\"used_mb\":${mem_used},\"total_mb\":${mem_total}}"
    fi
  else
    _warn "Usage" "could not read memory stats"
    json_add "memory" "warn" "free -m failed" "{}"
  fi
else
  echo "   (skipped)"
fi

# ── 7. Cron ──────────────────────────────────────────────────────────────────
section "Cron"

if ! should_skip "cron"; then
  cron_output=$(hermes cron list 2>/dev/null || true)
  cron_count=$(echo "$cron_output" | grep -c "job_id\|active\|pending\|running" 2>/dev/null || echo "0")
  if [ "$cron_count" -gt 0 ] 2>/dev/null; then
    _ok "Jobs" "${cron_count} registered"
    json_add "cron" "ok" "${cron_count} cron jobs registered" "{\"count\":${cron_count}}"
  else
    # Cron might not be available in this context — don't fail
    _ok "Jobs" "none registered (expected on fresh boot)"
    json_add "cron" "ok" "no cron jobs yet" "{\"count\":0}"
  fi
else
  echo "   (skipped)"
fi

# ── 8. Ollama ───────────────────────────────────────────────────────────────
section "Ollama"

if ! should_skip "ollama"; then
  # 1. Binary
  if command -v ollama >/dev/null 2>&1; then
    _ok "Binary" "$(ollama --version 2>/dev/null || echo 'installed')"
  else
    _fail "Binary" "ollama not in PATH"
  fi

  # 2. API responds
  OLLAMA_API=$(curl -s --max-time 5 http://localhost:11434/api/tags 2>/dev/null || echo "")
  if [ -n "$OLLAMA_API" ]; then
    _ok "API" "responding on :11434"
  else
    _fail "API" "no response from :11434"
  fi

  # 3. Model listed — retry up to 15s (server may still be scanning models)
  MODEL_LISTED=0
  for _attempt in 1 2 3 4 5; do
    MODEL_LISTED=$(ollama list 2>/dev/null | grep -c "nomic-embed-text" || true)
    [ -z "$MODEL_LISTED" ] && MODEL_LISTED=0
    [ "$MODEL_LISTED" -gt 0 ] && break
    sleep 3
  done
  if [ "$MODEL_LISTED" -gt 0 ]; then
    _ok "Model" "nomic-embed-text available"
  else
    # Filesystem fallback: check if model files exist on disk (server may be slow to load)
    MODEL_MANIFEST="$HOME/.ollama/models/manifests/registry.ollama.ai/library/nomic-embed-text/latest"
    if [ -f "$MODEL_MANIFEST" ]; then
      _warn "Model" "nomic-embed-text on disk but not listed by server (loading slow)"
    else
      _warn "Model" "nomic-embed-text not found on disk"
    fi
  fi

  # 4. Embedding generation — retry after model check (model may have loaded during retries above)
  EMBED_RESULT=""
  for _attempt in 1 2 3; do
    EMBED_RESULT=$(curl -s --max-time 30 -X POST http://localhost:11434/api/embed \
      -d '{"model":"nomic-embed-text","input":"hello world"}' 2>/dev/null || echo "")
    if echo "$EMBED_RESULT" | grep -q '"embeddings"'; then
      break
    fi
    sleep 3
  done
  if echo "$EMBED_RESULT" | grep -q '"embeddings"'; then
    EMBED_DIM=$(echo "$EMBED_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['embeddings'][0]))" 2>/dev/null || echo "?")
    _ok "Embedding" "generated (dim=${EMBED_DIM})"
  else
    _warn "Embedding" "failed to generate embedding (non-critical)"
  fi
else
  echo "   (skipped)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
section "Summary"
echo ""
if [ "$CRITICAL" -gt 0 ]; then
  echo "  ${RED}${BOLD}FAILED${NC} — ${CRITICAL} critical, ${WARNINGS} warning(s)"
  EXIT_CODE=2
elif [ "$WARNINGS" -gt 0 ]; then
  echo "  ${YELLOW}${BOLD}WARNINGS${NC} — ${WARNINGS} warning(s), 0 critical"
  EXIT_CODE=1
else
  echo "  ${GREEN}${BOLD}PASSED${NC} — all checks ok"
  EXIT_CODE=0
fi
echo ""

# ── Write JSON report ────────────────────────────────────────────────────────
rm -f "$REPORT_FILE" 2>/dev/null || true
cat > "$REPORT_FILE" <<EOF || true
{
  "timestamp": "$TIMESTAMP",
  "exit_code": $EXIT_CODE,
  "critical": $CRITICAL,
  "warnings": $WARNINGS,
  "checks": $JSON_RESULTS
}
EOF

# ── Telegram delivery (auto-discovered from Hermes config) ──────────────────
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
# Fall back to Hermes .env credential store if not set in env
if [ -z "$TELEGRAM_BOT_TOKEN" ] && [ -f "$HOME/.hermes/.env" ]; then
  TELEGRAM_BOT_TOKEN=$(grep '^TELEGRAM_BOT_TOKEN=' "$HOME/.hermes/.env" | head -1 | sed 's/^TELEGRAM_BOT_TOKEN=//' | tr -d '"' || true)
fi
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
# Fall back to TELEGRAM_HOME_CHANNEL env var (Hermes convention)
if [ -z "$TELEGRAM_CHAT_ID" ]; then
  TELEGRAM_CHAT_ID="${TELEGRAM_HOME_CHANNEL:-}"
fi
# Fall back to Hermes .env credential store
if [ -z "$TELEGRAM_CHAT_ID" ] && [ -f "$HOME/.hermes/.env" ]; then
  TELEGRAM_CHAT_ID=$(grep '^TELEGRAM_HOME_CHANNEL=' "$HOME/.hermes/.env" | head -1 | sed 's/^TELEGRAM_HOME_CHANNEL=//' | tr -d '"' || true)
fi
# Fall back to config.yaml (backward compat)
if [ -z "$TELEGRAM_CHAT_ID" ] && [ -f "$HERMES_CONFIG" ]; then
  TELEGRAM_CHAT_ID=$(grep -A10 '^telegram:' "$HERMES_CONFIG" 2>/dev/null | grep 'chat_id' | head -1 | sed 's/.*chat_id: *//' | tr -d '" ' | tr -d ' ') || true
  if [ -z "$TELEGRAM_CHAT_ID" ]; then
    TELEGRAM_CHAT_ID=$(grep -A10 '^telegram:' "$HERMES_CONFIG" 2>/dev/null | grep 'allowed_chats' | head -1 | sed 's/.*allowed_chats: *//' | tr -d '" ' | tr -d ' ') || true
  fi
fi

if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
  # Build a compact summary for Telegram
  SUMMARY="${EXIT_CODE}: "
  if [ "$CRITICAL" -gt 0 ]; then
    SUMMARY+="🔴 ${CRITICAL} critical, ${WARNINGS} warnings"
  elif [ "$WARNINGS" -gt 0 ]; then
    SUMMARY+="🟡 ${WARNINGS} warnings"
  else
    SUMMARY+="🟢 all ok"
  fi

  TEXT="*Hermes-WebTop Health Report*"
  TEXT+="\nStatus: ${SUMMARY}"
  TEXT+="\n╰ $(date -u +'%Y-%m-%d %H:%M UTC')"

  # Add critical failure details
  if [ "$CRITICAL" -gt 0 ]; then
    TEXT+="\n\n*Failures:*"
    echo "$JSON_RESULTS" | python3 -c "
import json,sys
results = json.load(sys.stdin)
for r in results:
    if r['status'] == 'fail':
        print(f'• {r[\"name\"]}: {r[\"message\"]}')
" 2>/dev/null | while IFS= read -r line; do
      TEXT+="\n${line}"
    done
  fi

  # Add warnings summary
  if [ "$WARNINGS" -gt 0 ]; then
    CRT=$CRITICAL
    echo "$JSON_RESULTS" | python3 -c "
import json,sys
results = json.load(sys.stdin)
warns = [r for r in results if r['status'] == 'warn']
if warns:
    print('\\n*Warnings:*')
    for w in warns:
        print(f'• {w[\"name\"]}: {w[\"message\"]}')
" 2>/dev/null | while IFS= read -r line; do
      TEXT+="\n${line}"
    done
  fi

  # Send via Telegram Bot API
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=${TEXT}" \
    -d "parse_mode=Markdown" \
    -d "disable_web_page_preview=true" \
    --max-time 10 >/dev/null 2>&1 && echo "  [telegram] notification sent" || echo "  [telegram] failed to send"
else
  echo "  [telegram] not configured — stdout only (set TELEGRAM_BOT_TOKEN and TELEGRAM_HOME_CHANNEL in ~/.hermes/.env)"
fi

exit "$EXIT_CODE"
