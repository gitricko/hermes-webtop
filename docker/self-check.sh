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

# ── 0. Cleanup ───────────────────────────────────────────────────────────────
# Purge stale ACP sessions from state.db. ACP sessions are VSCode/IDE extension
# sessions that persist in state.db across container reboots. Some may still be
# recoverable (if their saved billing_provider still exists in the current
# config), others are unrecoverable (provider was removed/renamed).
#
# This checks each session individually: only deletes sessions whose
# billing_provider no longer matches a configured provider, so recoverable
# sessions from the same container lifetime are preserved.
# section "Cleanup"
# STATE_DB="${HOME:-/config}/.hermes/state.db"
# if [ -f "$STATE_DB" ]; then
#   python3 -c "
# import sqlite3, os, yaml

# db_path = os.path.expanduser('$STATE_DB')
# cfg_path = os.path.expanduser('~/.hermes/config.yaml')

# try:
#     # 1. Build set of configured providers
#     configured = set()
#     with open(cfg_path) as f:
#         cfg = yaml.safe_load(f) or {}
#     configured.update((cfg.get('providers') or {}).keys())
#     configured.update((cfg.get('custom_providers') or {}).keys())
#     mc = cfg.get('model', {})
#     if isinstance(mc, dict) and mc.get('provider'):
#         configured.add(mc['provider'])

#     # 2. Check each ACP session
#     db = sqlite3.connect(db_path)
#     rows = db.execute('''
#         SELECT id, billing_provider FROM sessions
#         WHERE source='acp'
#     ''').fetchall()
    
#     purged = 0
#     kept = 0
#     for sid, bp in rows:
#         if bp is None or bp in configured:
#             kept += 1
#         else:
#             purged += 1
#             db.execute('DELETE FROM sessions WHERE id=?', (sid,))
#     db.commit()
#     db.close()
#     print(f'{purged} {kept}')
# except Exception:
#     print('-1 -1')
# " 2>/dev/null | while read purged kept; do
#     [ -z "$purged" ] && purged=0
#     [ -z "$kept" ] && kept=0
#     if [ "$purged" -gt 0 ] 2>/dev/null; then
#       _ok "ACP sessions" "purged ${purged} stale session(s), kept ${kept}"
#       json_add "cleanup:acp-sessions" "ok" "purged ${purged} stale, kept ${kept}" "{\"purged\":${purged},\"kept\":${kept}}"
#     elif [ "$purged" = "0" ] 2>/dev/null && [ "$kept" -ge 0 ] 2>/dev/null; then
#       _ok "ACP sessions" "none to clean (${kept} kept)"
#       json_add "cleanup:acp-sessions" "ok" "no stale sessions" "{\"kept\":${kept}}"
#     else
#       _warn "ACP sessions" "cleanup query failed"
#       json_add "cleanup:acp-sessions" "warn" "cleanup failed" "{}"
#     fi
#   done
# else
#   _ok "ACP sessions" "no state.db yet"
#   json_add "cleanup:acp-sessions" "ok" "state.db not found" "{}"
# fi

# ── 1. Services ──────────────────────────────────────────────────────────────
section "Services"

if ! should_skip "services"; then
  # Poll all service ports until all respond or timeout
  PORT_POLL_TIMEOUT=60
  POLL_STARTED_AT=$(date +%s)
  declare -A RESPONDED=([3000]="" [8888]="" [7352]="" [20128]="")
  echo ""
  echo "=== Polling Service Ports (${PORT_POLL_TIMEOUT}s timeout) ==="

  while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - POLL_STARTED_AT))

    if [ "$ELAPSED" -gt "$PORT_POLL_TIMEOUT" ]; then
      echo ""
      echo "→ FAIL: Port poll timeout after ${PORT_POLL_TIMEOUT}s — not all services responded"
      for pair in "3000:WebTop" "8888:CodeServer" "7352:ModelRelay" "20128:OmniRoute"; do
        PORT="${pair%%:*}"
        NAME="${pair##*:}"
        if [ "${RESPONDED[$PORT]}" != "true" ]; then
          echo "  • $NAME (:$PORT) — ❌ never responded"
        fi
      done
    fi

    for pair in "3000:WebTop" "8888:CodeServer" "7352:ModelRelay" "20128:OmniRoute"; do
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
    for port in 3000 8888 7352 20128; do
      if [ "${RESPONDED[$port]}" != "true" ]; then
        ALL_RESPONDED=false
        break
      fi
    done

    if [ "$ALL_RESPONDED" = "true" ]; then
      echo ""
      echo "→ PASS: All service ports responded within ${ELAPSED}s"
      break
    fi

    sleep 5
  done

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
    _fail "Config" "no config at ${HERMES_CONFIG}"
    json_add "hermes:config" "fail" "hermes config file not found" "{}"
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
cat > "$REPORT_FILE" <<EOF
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
