#!/bin/bash
source /custom-cont-init.d/common.sh || exit 1

HERMES_HOME="${HERMES_HOME:-/config/.hermes}"
PENDING_MARKER="${HERMES_HOME}/.hermes-update-in-progress"

# ---------------------------------------------------------------------------
# 0. Detect a stuck self-update BEFORE doing anything else.
# ---------------------------------------------------------------------------
if [[ -f "${PENDING_MARKER}" ]]; then
  echo "[start-hermes] WARNING: stale update-in-progress marker found:"
  cat "${PENDING_MARKER}" 2>/dev/null || true
  echo "[start-hermes] The hermes gateway will likely report 'draining (update_paused)'."
  echo "[start-hermes] If this persists, run 'hermes update' from a minimal shell (env -i)."
fi

# ---------------------------------------------------------------------------
# 1. Ownership — only when something actually mismatches (cheap find check).
# ---------------------------------------------------------------------------
fix_ownership_if_needed() {
  local dir="$1"
  [[ -d "${dir}" ]] || return 0
  if [[ -n "$(find "${dir}" \( ! -user abc -o ! -group abc \) -print -quit 2>/dev/null)" ]]; then
    echo "[start-hermes] ownership mismatch in ${dir}; fixing..."
    chown abc:abc -R "${dir}" || echo "[start-hermes] ERROR: chown ${dir} failed"
  fi
}

fix_ownership_if_needed "/usr/local/lib/hermes-agent"
fix_ownership_if_needed "${HERMES_HOME}"

# ---------------------------------------------------------------------------
# 2. Drop into the abc user with a MINIMAL, controlled environment (E2BIG fix).
# ---------------------------------------------------------------------------
(
runuser -l abc <<'EOF'
source /custom-cont-init.d/common.sh || exit 1

export PATH="/usr/local/bin:/usr/bin:/bin"
export HOME="${HOME}"
export HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
unset LD_LIBRARY_PATH LD_PRELOAD HTTP_PROXY HTTPS_PROXY http_proxy https_proxy 2>/dev/null || true

cd "${HOME}" || cd /

mkdir -p "${HERMES_HOME}/logs"

# ---------------------------------------------------------------------------
# 3. Idempotent config: only set keys that are actually missing.
# ---------------------------------------------------------------------------
set_if_missing() {
  local key="$1" value="$2"
  if ! hermes config get "${key}" >/dev/null 2>&1; then
    hermes config set "${key}" "${value}" || echo "[start-hermes] WARNING: failed to set ${key}=${value}"
  fi
}

if [ -d "${HERMES_HOME}/logs" ] && [ -z "$(ls -A "${HERMES_HOME}/logs" 2>/dev/null)" ]; then
  echo "[start-hermes] first run detected, applying default config..."
fi

while IFS='|' read -r key value; do
  [[ -z "${key}" ]] && continue
  set_if_missing "${key}" "${value}"
done <<'CFG'
terminal.cwd|${PWD}
display.busy_input_mode|steer
model.default|auto-fastest
model.provider|omniroute
providers.omniroute.base_url|http://localhost:20128/v1
providers.omniroute.api_key|no-key-needed
providers.9router.base_url|http://localhost:7352/v1
providers.9router.api_key|no-key-needed
fallback_providers.provider|9router
fallback_providers.model|auto-fastest
auxiliary.title_generation.model|auto-fastest
auxiliary.title_generation.provider|9router
auxiliary.vision.model|auto-fastest
auxiliary.vision.provider|9router
auxiliary.compression.model|auto-fastest
auxiliary.compression.provider|9router
approvals.mode|off
memory.memory_enabled|true
memory.user_profile_enabled|true
memory.provider|mnemon
agent.max_turns|120
kanban.failure_limit|3
CFG

# First-run seeding of skill + .hermes.md (only if missing)
if [ ! -f "${HOME}/.hermes/skills/memory-automation/SKILL.md" ]; then
  echo "[start-hermes] Installing Skill: memory-automation.md"
  mkdir -p "${HOME}/.hermes/skills/memory-automation"
  cp /custom-cont-init.d/skill-memory-automation.md "${HOME}/.hermes/skills/memory-automation/SKILL.md" 2>/dev/null || true
  chown abc:abc "${HOME}/.hermes/skills/memory-automation/SKILL.md" 2>/dev/null || true
fi

if [ ! -f "${HOME}/.hermes.md" ]; then
  echo "[start-hermes] Populate .hermes.md"
  cp /custom-cont-init.d/.hermes.md "${HOME}/.hermes.md" 2>/dev/null || true
  chown abc:abc "${HOME}/.hermes.md" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 4. Telegram gateway dependency (idempotent)
# ---------------------------------------------------------------------------
ensure_ownership "/usr/local/lib/hermes-agent/venv" 2>/dev/null || true
/usr/local/lib/hermes-agent/venv/bin/python -m ensurepip --upgrade >/dev/null 2>&1 || true
ln -s /usr/local/lib/hermes-agent/venv/bin/pip3 /usr/local/lib/hermes-agent/venv/bin/pip 2>/dev/null || true
/usr/local/lib/hermes-agent/venv/bin/pip install python-telegram-bot >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 5. Mnemon plugin (synced before gateway starts)
# ---------------------------------------------------------------------------
echo "[start-hermes] Checking mnemon provider..."
rm -rf /tmp/mnemon_repo
if git clone https://github.com/gitricko/hermes-plugin-mnemon /tmp/mnemon_repo >/dev/null 2>&1; then
  if [ ! -d "${HOME}/.hermes/plugins/mnemon" ] || ! diff -r -q -x __pycache__ "${HOME}/.hermes/plugins/mnemon" "/tmp/mnemon_repo/mnemon" >/dev/null 2>&1; then
    echo "[start-hermes] Mnemon plugin is missing or out of date. Updating..."
    mkdir -p "${HOME}/.hermes/plugins"
    rm -rf "${HOME}/.hermes/plugins/mnemon"
    cp -r "/tmp/mnemon_repo/mnemon" "${HOME}/.hermes/plugins/mnemon"
    echo "[start-hermes] Mnemon plugin updated successfully."
  else
    echo "[start-hermes] Mnemon plugin is up to date."
  fi
  rm -rf /tmp/mnemon_repo
else
  echo "[start-hermes] WARNING: Failed to clone gitricko/hermes-plugin-mnemon repository."
fi

# ---------------------------------------------------------------------------
# 6. Start the gateway without double-starting or fighting the update fence.
# ---------------------------------------------------------------------------
gw_state="$(hermes gateway status 2>&1 || true)"
if printf '%s' "${gw_state}" | grep -qi '"state":"running"\|Gateway is running\|running'; then
  echo "[start-hermes] gateway already running, leaving it alone"
elif printf '%s' "${gw_state}" | grep -qi 'update_paused'; then
  echo "[start-hermes] gateway fenced by an in-progress update (update_paused)."
  echo "               run 'hermes update' to unstick it; not starting here."
else
  echo "[start-hermes] Starting Hermes Gateway..."
  mkdir -p "${HERMES_HOME}/logs"
  nohup hermes gateway run --no-supervise > "${HERMES_HOME}/logs/gateway.log" 2>&1 &
  disown
fi

# ---------------------------------------------------------------------------
# 7. Dashboard (socat + hermes dashboard)
# ---------------------------------------------------------------------------
ensure_ownership "/usr/local/lib/hermes-agent/hermes_cli" 2>/dev/null || true
ensure_ownership "/usr/local/lib/hermes-agent/web" 2>/dev/null || true
echo "[start-hermes] Starting Hermes Dashboard..."
nohup socat TCP4-LISTEN:9119,fork,reuseaddr TCP4:127.0.0.1:9009 > "${HERMES_HOME}/logs/socat-9119.log" 2>&1 &
nohup hermes dashboard --port 9009 --no-open --skip-build > "${HERMES_HOME}/logs/dashboard.log" 2>&1 &

# Mnemon USER.md seed
if [ ! -f "${HOME}/.hermes/memories/USER.md" ]; then
  echo "[start-hermes] Setting up Mnemon USER.md..."
  mkdir -p "${HOME}/.hermes/memories"
  echo 'Always use Mnemon (mnemon_remember / mnemon_recall) as primary memory provider instead of the standard memory() tool. Mnemon has no char limit. Only fall back to memory() for structured preference data (target=user or memory).' > "${HOME}/.hermes/memories/USER.md"
  chown abc:abc "${HOME}/.hermes/memories/USER.md" 2>/dev/null || true
fi

# Wait for dashboard to be ready
echo "[start-hermes] Waiting for Hermes dashboard to become healthy..."
for i in $(seq 1 200); do
  if curl -s -o /dev/null -w "%{http_code}" http://localhost:9119 2>/dev/null | grep -q "200\|302\|401"; then
    echo "[start-hermes] Dashboard ready after $((i * 3)) seconds."
    break
  fi
  if [ "$i" -eq 200 ]; then
    echo "[start-hermes] WARNING: Dashboard did not respond within 600 seconds. Check ${HOME}/.hermes/logs/dashboard.log"
  fi
  sleep 3
done

echo "[start-hermes] All hermes-agent services started and ready."

# Boot-time self-check
echo "[start-hermes] Running boot-time health self-check..."
/usr/local/bin/self-check || echo "[start-hermes] WARNING: self-check reported issues"

EOF
) &

sleep 5
