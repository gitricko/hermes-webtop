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

# v0.23.x launcher lives at $INSTALL_DIR/.hermes/bin, exposed image-wide by
# the /usr/local/bin/hermes symlink from the Dockerfile (root's ~/.local/bin
# wiring never reaches this runuser -l abc / s6 context). Bare `hermes` calls
# below (config set, gateway, dashboard) die with "No such file or directory"
# without it — CI hang: port 9009 never listens, health loop spins 600s.
export PATH="/usr/local/bin:/usr/bin:/bin"
if ! command -v hermes >/dev/null 2>&1; then
  echo "[start-hermes] FATAL: hermes launcher not found in PATH (${PATH})" >&2
  exit 1
fi
export HOME="${HOME}"
export HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
unset LD_LIBRARY_PATH LD_PRELOAD HTTP_PROXY HTTPS_PROXY http_proxy https_proxy 2>/dev/null || true

cd "${HOME}" || cd /

mkdir -p "${HERMES_HOME}/logs"

# ---------------------------------------------------------------------------
# 3. Config seeding — classified by content, NOT by a side-channel marker.
#
# History: the original "fresh install?" gate checked that $HERMES_HOME/logs
# was empty and silently skipped the whole block on fresh v0.23.x images
# (installer dirties logs/ at BUILD time; parallel start-codeserver races it)
# — proven by run 43261010629. The follow-up sentinel-marker fix worked but
# left the gate dependent on a bookkeeping file.
#
# The honest signal is the config itself. Two independent facts (verified in
# v0.23.1 source, hermes_cli/config.py:seed_config_file -> shutil.copy2):
#   * a pristine config.yaml is BYTE-IDENTICAL to cli-config.yaml.example
#     (md5 aef2d235… in both the run-7 artifact and the v0.23.1 tree), and
#   * stock contains NONE of our webtop keys (omniroute/9router/auxiliary
#     greps over the 131 KB template all return 0), while our block writes
#     providers.omniroute, providers.9router, auxiliary.*.
# So classification needs no state file at all:
#
#   SEED      config.yaml missing            (brand-new home)
#   SEED      no webtop keys present         (stock template, untouched OR
#                                       hermes-migrated — neither carries user intent)
#   PRESERVE  webtop keys present            (we applied, or user customized)
#
# Fallback direction (conservative for the USER, loud for us):
#   * missing webtop keys + no baseline/hash -> still SEED (markers absent =
#     unconfigured by us; seed is idempotent) — never PRESERVE an unconfigured file.
#   * webtop keys present + hash unexpectedly matches stock -> PRESERVE + WARN.
#
# The three webtop markers below are guaranteed absent from stock (see above)
# and are written by the apply block, so they are perfect discriminators.
# ---------------------------------------------------------------------------
CONFIG_FILE="${HERMES_HOME}/config.yaml"
STOCK_HASH_FILE="/usr/local/share/hermes-webtop/stock-config.sha256"
WEBTOP_MARKERS="localhost:20128/v1 localhost:7352/v1 auxiliary.vision"

should_seed=""
may_warn=""
if [ ! -f "${CONFIG_FILE}" ]; then
  should_seed="config.yaml missing (fresh home)"
else
  # Corroborating hash check (non-fatal): proves the file is the untouched stock
  # template when it matches the image-baked baseline. Only used to enrich the
  # seed reason; it must NEVER flip an otherwise-correct decision.
  STOCK_SHA="$(cat "${STOCK_HASH_FILE}" 2>/dev/null | tr -d '[:space:]')"
  CUR_SHA="$(command -v sha256sum >/dev/null 2>&1 && sha256sum "${CONFIG_FILE}" 2>/dev/null | cut -d' ' -f1 | tr -d '[:space:]')"

  # Primary discriminator: are any of OUR webtop keys present?
  HAS_MARKERS=1
  for m in ${WEBTOP_MARKERS}; do
    grep -qF -- "${m}" "${CONFIG_FILE}" || { HAS_MARKERS=0; break; }
  done

  if [ "${HAS_MARKERS}" -eq 0 ]; then
    # No webtop keys = unconfigured by us. Seed (idempotent). Enrich with hash
    # if available: match = pristine template, mismatch = hermes normalized it
    # first (the known run-7 race). Either way the file carries no user intent.
    if [ -n "${CUR_SHA}" ] && [ "${CUR_SHA}" = "${STOCK_SHA}" ]; then
      should_seed="config.yaml is the unmodified stock template (hash match)"
    else
      should_seed="config.yaml has no webtop keys (unconfigured)"
    fi
  else
    # Webtop keys present = we (or the user on top of us) configured this file.
    # Preserve unconditionally — never re-apply over real user state.
    if [ -n "${CUR_SHA}" ] && [ "${CUR_SHA}" = "${STOCK_SHA}" ]; then
      may_warn="webtop keys present yet hash matches stock baseline (unexpected)"
    fi
    echo "[start-hermes] config already carries webtop markers; preserving existing config."
  fi
fi

if [ -n "${should_seed}" ]; then
  echo "[start-hermes] seeding config: ${should_seed}"
  apply_config() {
    hermes config set "$1" "$2" || echo "[start-hermes] WARNING: failed to set $1=$2"
  }
  # Same as apply_config but passes --force: needed for keys read by hermes
  # (e.g. auxiliary.*.fallback_chain) that are not declared in DEFAULT_CONFIG,
  # where `config set` prints an unknown-key notice (still writes).
  apply_config_force() {
    hermes config set --force "$1" "$2" || echo "[start-hermes] WARNING: failed to set $1=$2 (forced)"
  }
  apply_config "terminal.cwd" "${PWD}"
  apply_config "display.busy_input_mode" "steer"
  apply_config "model.default" "auto-fastest"
  apply_config "model.provider" "omniroute"
  apply_config "providers.omniroute.base_url" "http://localhost:20128/v1"
  apply_config "providers.omniroute.api_key" "no-key-needed"
  apply_config "providers.9router.base_url" "http://localhost:7352/v1"
  apply_config "providers.9router.api_key" "no-key-needed"
  apply_config "fallback_providers.provider" "9router"
  apply_config "fallback_providers.model" "auto-fastest"
  apply_config "auxiliary.title_generation.model" "auto-fastest"
  apply_config "auxiliary.title_generation.provider" "9router"
  # Auxiliary vision route: image analysis goes to OmniRoute, falls back to 9Router.
  # fallback_chain key is not in DEFAULT_CONFIG, so it requires config set --force.
  apply_config "auxiliary.vision.model" "auto-fastest"
  apply_config "auxiliary.vision.provider" "omniroute"
  apply_config_force "auxiliary.vision.fallback_chain" '[{provider: 9router, model: auto-fastest}]'
  apply_config "auxiliary.compression.model" "auto-fastest"
  apply_config "auxiliary.compression.provider" "9router"
  apply_config "approvals.mode" "off"
  apply_config "memory.memory_enabled" "true"
  apply_config "memory.user_profile_enabled" "true"
  apply_config "memory.provider" "mnemon"
  apply_config "agent.max_turns" "120"
  apply_config "kanban.failure_limit" "3"
  echo "[start-hermes] config defaults applied."
fi

if [ -n "${may_warn}" ]; then
  echo "[start-hermes] WARNING: ${may_warn}" >&2
fi

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
# NOTE: match ONLY the positive markers. The old bare "running" alternative
# matched the "Gateway is NOT running" line the CLI prints when stopped,
# so the gateway was never started on a fresh container (regression —
# see CI run 40903091557 / PR #61).
if printf '%s' "${gw_state}" | grep -q 'Gateway is running\|"state":"running"\|✓ Gateway'; then
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
