#!/bin/bash
# Dependency version checker for Hermes Webtop.
# Compares versions pinned in docker/Dockerfile (single source of truth)
# against npm registry / GitHub tags / nodejs.org.
#
# Usage: bash scripts/check-deps.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERFILE="${SCRIPT_DIR}/../docker/Dockerfile"

# --- current versions: read from Dockerfile ARGs, never hardcode here ---
arg() { sed -n "s/^ARG ${1}=//p" "${DOCKERFILE}" | head -1 | tr -d '"'; }

HERMES_VERSION="$(arg HERMES_VERSION | sed 's/^v//')"
NINEROUTER_VERSION="$(arg NINEROUTER_VERSION)"
OMNIROUTE_VERSION="$(arg OMNIROUTE_VERSION)"
PI_VERSION="$(arg PI_VERSION)"
NODE_VERSION="$(arg NODE_VERSION)"
OLLAMA_VERSION="$(arg OLLAMA_VERSION)"
CODE_SERVER_VERSION="$(arg CODE_SERVER_VERSION)"
MNEMON_VERSION="$(arg MNEMON_VERSION)"
HERDR_VERSION="$(arg HERDR_VERSION)"

# --- latest-version sources ---
npm_latest() {  # $1 = npm package name
    curl -s "https://registry.npmjs.org/$1/latest" \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null \
        || echo "?"
}

gh_latest() {  # $1 = owner/repo -> newest stable tag (rc/beta/alpha/dev excluded, leading v stripped)
    curl -s "https://api.github.com/repos/$1/tags" \
        | python3 -c "
import json,sys,re
d = json.load(sys.stdin)
if not isinstance(d, list) or not d:
    print('?'); sys.exit()
pre = re.compile(r'(?i)(rc|beta|alpha|preview|pre[-.]|dev|nightly|canary|next)')
stable = [t['name'] for t in d if not pre.search(t['name'])]
print(stable[0].lstrip('v') if stable else '?')" 2>/dev/null \
        || echo "?"
}

node_latest() {  # $1 = current version -> newest in the same major line
    curl -s "https://nodejs.org/dist/index.json" \
        | python3 -c "
import json,sys
cur = sys.argv[1]
major = cur.split('.')[0]
d = json.load(sys.stdin)
vs = [x['version'].lstrip('v') for x in d if x['version'].startswith('v'+major+'.')]
print(max(vs, key=lambda v: [int(p) for p in v.split('.')]) if vs else '?')" "$1" 2>/dev/null \
        || echo "?"
}

check() {  # $1 = name, $2 = current, $3 = latest
    if [ "$3" = "?" ]; then
        printf '  %-18s current=%s | latest=UNAVAILABLE\n' "$1" "$2"
    elif [ "$3" != "$2" ]; then
        printf '  %-18s current=%s | latest=%s [UPDATE AVAILABLE]\n' "$1" "$2" "$3"
    else
        printf '  %-18s current=%s | latest=%s [OK]\n' "$1" "$2" "$3"
    fi
}

echo "=== Hermes Webtop Dependency Check ==="
echo "(current versions read from docker/Dockerfile ARGs)"
echo ""
echo "NPM packages:"
check "9router"         "${NINEROUTER_VERSION}"   "$(npm_latest 9router)"
check "omniroute"       "${OMNIROUTE_VERSION}"    "$(npm_latest omniroute)"
check "pi-coding-agent" "${PI_VERSION}"           "$(npm_latest @earendil-works/pi-coding-agent)"
echo ""
echo "GitHub-release binaries:"
check "hermes-agent"    "${HERMES_VERSION}"       "$(gh_latest NousResearch/hermes-agent)"
check "node"            "${NODE_VERSION}"         "$(node_latest "${NODE_VERSION}")"
check "ollama"          "${OLLAMA_VERSION}"       "$(gh_latest ollama/ollama)"
check "code-server"     "${CODE_SERVER_VERSION}"  "$(gh_latest coder/code-server)"
check "mnemon"          "${MNEMON_VERSION}"       "$(gh_latest mnemon-dev/mnemon)"
check "herdr"           "${HERDR_VERSION}"        "$(gh_latest ogulcancelik/herdr)"