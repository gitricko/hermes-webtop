#!/bin/bash
# sync-badges.sh — keep the version badges in README.md aligned with
# docker/Dockerfile ARGs (single source of truth: the Dockerfile).
#
# Usage:
#   bash scripts/sync-badges.sh            # update the managed section in README.md
#   bash scripts/sync-badges.sh --check    # read-only: 0 = in sync, 1 = drift (lists diff)
#
# The managed block is delimited by explicit begin/end markers so repeated
# runs are idempotent and the block can be regenerated at any time.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKERFILE="${REPO_ROOT}/docker/Dockerfile"
README="${REPO_ROOT}/README.md"

if [ ! -f "$DOCKERFILE" ] || [ ! -f "$README" ]; then
    echo "sync-badges: missing $DOCKERFILE or $README" >&2
    exit 1
fi

CHECK_ONLY=0
case "${1:-}" in
    --check) CHECK_ONLY=1 ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "")      ;;
    *) echo "unknown flag: $1 (try --check or -h)" >&2; exit 2 ;;
esac

BEGIN_MARK='<!-- versions-begin: managed by scripts/sync-badges.sh — do not edit between markers -->'
END_MARK='<!-- versions-end -->'

# First (defining) value of an ARG in the Dockerfile, quotes stripped.
arg() { sed -n "s/^ARG ${1}=//p" "$DOCKERFILE" | head -1 | tr -d '"'; }

# Badge table: ARG name | destination link | color | logo
BADGES=(
    "HERMES_VERSION|https://github.com/NousResearch/hermes-agent|purple|github"
    "PI_VERSION|https://pi.dev|brown|github"
    "OMNIROUTE_VERSION|https://www.npmjs.com/package/omniroute|orange|npm"
    "NINEROUTER_VERSION|https://www.npmjs.com/package/9router|green|npm"
    "OLLAMA_VERSION|https://github.com/ollama/ollama|yellow|ollama"
    "MNEMON_VERSION|https://github.com/mnemon-dev/mnemon|pink|github"
    "NODE_VERSION|https://nodejs.org|brightgreen|node.js"
    "CODE_SERVER_VERSION|https://github.com/coder/code-server|blue|code"
    "HERDR_VERSION|https://github.com/herdrdev/herdr|red|terminal"
)

# Display label per ARG (falls back to a humanized ARG name).
# NOTE: shields.io static-badge labels must not contain hyphens
# ("code-server" renders a fake 200 "404: badge not found" SVG) — use spaces.
label() {
    case "$1" in
        HERMES_VERSION)      echo "Hermes Agent" ;;
        PI_VERSION)          echo "PI Agent" ;;
        OMNIROUTE_VERSION)   echo "OmniRoute" ;;
        NINEROUTER_VERSION)  echo "9Router" ;;
        OLLAMA_VERSION)      echo "Ollama" ;;
        MNEMON_VERSION)      echo "Mnemon" ;;
        NODE_VERSION)        echo "Node.js" ;;
        CODE_SERVER_VERSION) echo "Code Server" ;;
        HERDR_VERSION)       echo "herdr" ;;
        *) echo "${1%_VERSION}" ;;
    esac
}

# URL-encode badge label (spaces must be %20 for shields.io).
enc() { python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"; }

# Build the full managed block (BEGIN marker + pills + END marker), no trailing NL.
current="$(
    {
        printf '%s\n' "$BEGIN_MARK"
        for entry in "${BADGES[@]}"; do
            IFS='|' read -r vname link color logo <<< "$entry"
            v="$(arg "$vname")"
            if [ -z "$v" ]; then
                echo "sync-badges: ARG $vname has no value in Dockerfile" >&2
                exit 1
            fi
            d="$(label "$vname")"
            printf '  <a href="%s">\n    <img src="https://img.shields.io/badge/%s-%s-%s?logo=%s" alt="%s version">\n  </a>\n' \
                "$link" "$(enc "$d")" "$v" "$color" "$logo" "$d"
        done
        printf '%s' "$END_MARK"
    }
)"

# Extract the currently managed section from README.md (marker to marker, inclusive).
existing="$(awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0==b {inblk=1}
    inblk {print}
    inblk && $0==e {exit}
' "$README")" || true

if [ "$CHECK_ONLY" -eq 1 ]; then
    if [ -z "$existing" ]; then
        echo "DRIFT: README.md has no managed badge section (run: bash scripts/sync-badges.sh)"
        exit 1
    fi
    if [ "$existing" = "$current" ]; then
        echo "readme badges: in sync with docker/Dockerfile"
        exit 0
    fi
    echo "DRIFT: README.md badges out of sync with docker/Dockerfile:"
    diff <(printf '%s\n' "$existing") <(printf '%s\n' "$current") | sed 's/^/  /' || true
    exit 1
fi

if [ "$existing" = "$current" ]; then
    echo "readme badges: already in sync"
    exit 0
fi

# Splice: replace the marked block if present, else insert a new centered block
# right after the first closed badge paragraph (<p align="center">…</p>).
MANAGED_FILE="$(mktemp)"
trap 'rm -f "$MANAGED_FILE"' EXIT
printf '%s\n' "$current" > "$MANAGED_FILE"
python3 - "$README" "$BEGIN_MARK" "$END_MARK" "$MANAGED_FILE" <<'PYEOF'
import re, sys
path, begin, end, managed_file = sys.argv[1:5]
managed = open(managed_file).read().rstrip('\n')
text = open(path).read()
pat = re.compile(re.escape(begin) + r'.*?' + re.escape(end), re.S)
if pat.search(text):
    out = pat.sub(managed.replace('\\', '\\\\'), text, count=1)
    open(path, 'w').write(out)
    print('readme badges: updated managed section in README.md')
else:
    m = re.search(r'</p>', text)
    if not m:
        sys.exit('no insertion point found in README.md')
    at = m.end()
    out = text[:at] + '\n\n<p align="center">\n' + managed + '\n</p>\n' + text[at:]
    open(path, 'w').write(out)
    print('readme badges: inserted new managed section in README.md')
PYEOF

# Verify the write landed (self-check against the source of truth).
awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0==b {inblk=1}
    inblk {print}
    inblk && $0==e {exit}
' "$README" > "${MANAGED_FILE}.verify" 2>/dev/null || true
if [ "$(cat "${MANAGED_FILE}.verify" 2>/dev/null)" = "$current" ]; then
    echo "verified: README.md badges match docker/Dockerfile"
else
    echo "!! error: README.md badges could not be verified to match Dockerfile" >&2
    exit 1
fi
rm -f "${MANAGED_FILE}.verify"
