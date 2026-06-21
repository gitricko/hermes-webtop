#!/bin/bash
# shellcheck disable=SC2317
# SPDX-License-Identifier: MIT
#
# hermes-acp-patch -- Boot-time patch for Hermes ACP session restore
#
# When the VS Code extension reloads, it tries to restore the previous ACP
# session. If that session used a provider no longer in the current config
# (e.g. "custom" after switching to "omniroute"), the runtime resolution
# returns an empty api_key and init_agent raises "No LLM provider configured".
#
# This patch makes _restore retry with the current config's provider when
# the stored provider fails, so old sessions gracefully fall back to the
# live endpoint instead of blocking all new prompts.
#
# Target: /usr/local/lib/hermes-agent/acp_adapter/session.py
#   _restore() try/except block

set -euo pipefail

TARGET="/usr/local/lib/hermes-agent/acp_adapter/session.py"
PATCH_NAME="hermes-acp-session-restore"
PATCHED_MARKER="retrying with current config"

# Exit early if already patched
if grep -Fq "$PATCHED_MARKER" "$TARGET" 2>/dev/null; then
  echo "[$PATCH_NAME] already applied -- nothing to do"
  exit 0
fi

# For a robust multi-line replacement, use Python (not sed/patch).
# Variables TARGET/PATCH_NAME are not exported to the heredoc --
# they are hardcoded in the Python below for reliability.
python3 <<'PYEOF'
import sys

target = '/usr/local/lib/hermes-agent/acp_adapter/session.py'
pn = 'hermes-acp-session-restore'

old = """        try:
            agent = self._make_agent(
                session_id=session_id,
                cwd=cwd,
                model=model,
                requested_provider=requested_provider,
                base_url=restored_base_url,
                api_mode=restored_api_mode,
            )
        except Exception:
            logger.warning("Failed to recreate agent for ACP session %s", session_id, exc_info=True)
            return None"""

new = """        try:
            agent = self._make_agent(
                session_id=session_id,
                cwd=cwd,
                model=model,
                requested_provider=requested_provider,
                base_url=restored_base_url,
                api_mode=restored_api_mode,
            )
        except Exception:
            logger.warning(
                "Failed to recreate agent for ACP session %s with stored "
                "provider %r \u2014 retrying with current config",
                session_id, requested_provider,
            )
            try:
                agent = self._make_agent(
                    session_id=session_id,
                    cwd=cwd,
                    model=model,
                    # No requested_provider \u2014 uses current config provider
                )
            except Exception as exc2:
                logger.warning(
                    "Failed to recreate agent for ACP session %s even with "
                    "current config: %s",
                    session_id, exc2,
                )
                return None"""

with open(target) as f:
    content = f.read()

if new in content:
    print(f"[{pn}] already applied -- nothing to do")
    sys.exit(0)

if old in content:
    content = content.replace(old, new, 1)
    with open(target, 'w') as f:
        f.write(content)
    print(f"[{pn}] applied successfully")
    sys.exit(0)

print(f"[{pn}] patch site not found -- Hermes may have been updated")
sys.exit(1)
PYEOF
