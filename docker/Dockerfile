ARG HERMES_VERSION="v2026.8.13"
ARG OMNIROUTE_VERSION=3.8.49
ARG MODELRELAY_VERSION=1.18.0
ARG OLLAMA_VERSION=0.32.6
ARG NODE_VERSION=24.18.0
ARG CODE_SERVER_VERSION=4.131.0
ARG MNEMON_VERSION=0.1.17
ARG TARGETARCH

# Use the official Ollama image to get the binary
FROM ollama/ollama:${OLLAMA_VERSION} AS ollama-bin

# Get the binaries from official Node image
FROM node:${NODE_VERSION}-slim AS node-bin

# Use your preferred Webtop flavor as the base (e.g., Ubuntu, Alpine)
FROM lscr.io/linuxserver/webtop:ubuntu-mate

# Add gh apt repository
ARG TARGETARCH
RUN GH_ARCH="${GH_ARCH:-${TARGETARCH:-amd64}}"; \
    case "${GH_ARCH}" in \
      amd64|x86_64) GH_ARCH=amd64 ;; \
      arm64|aarch64) GH_ARCH=arm64 ;; \
      *) echo "Unsupported GH_ARCH: ${GH_ARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=${GH_ARCH} signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list 

# Install help utilities and clean up apt cache to reduce image size
RUN apt-get update && apt-get install -y htop zsh ripgrep gh remmina iputils-ping net-tools socat && rm -rf /var/lib/apt/lists/*

# Copy Node.js binaries and libraries
COPY --from=node-bin --chown=abc:abc /usr/local/bin/node /usr/local/bin/
COPY --from=node-bin --chown=abc:abc /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm

# Copy the Ollama binary from the official image
COPY --from=ollama-bin --chown=abc:abc /usr/bin/ollama /usr/local/bin/ollama

# Start desktop launchers and bootstrap scripts automatically when the desktop loads
RUN mkdir -p /custom-cont-init.d
# COPY --chown=abc:abc *.desktop /custom-cont-init.d
COPY --chown=abc:abc *.sh /custom-cont-init.d
COPY --chown=abc:abc *.json /custom-cont-init.d
COPY --chown=abc:abc *.md /custom-cont-init.d

# Move self-check to usr/local/bin to prevent it running as a boot-time init script
RUN mv /custom-cont-init.d/self-check.sh /usr/local/bin/self-check && chmod +x /usr/local/bin/self-check

# Install Hermes
ARG HERMES_VERSION
ENV HERMES_HOME=/config/.hermes
RUN curl -fsSL "https://raw.githubusercontent.com/NousResearch/hermes-agent/${HERMES_VERSION}/scripts/install.sh" | bash -s -- --skip-setup && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p ${HERMES_HOME} && \
    cd /usr/local/lib/hermes-agent && \
    CI=1 npm ci --include=dev --workspace web --silent 2>&1 || \
    CI=1 npm install --no-save --include=dev --workspace web --silent 2>&1 && \
    CI=1 npm run build -w web --silent 2>&1 && \
    npm cache clean --force && \
    echo "=== BUILD-TIME DEBUG ===" && \
    ls -la /usr/local/lib/hermes-agent/hermes_cli/web_dist/ 2>&1 | head -20 && \
    ls -la /config/.hermes/ 2>&1 && \
    cat /config/.hermes/web-ui-build-stamp.json 2>&1 && \
    cp -f /root/.hermes/web-ui-build-stamp.json ${HERMES_HOME}/web-ui-build-stamp.json 2>/dev/null || true && \
    HERMES_HOME=${HERMES_HOME} python3 <<'PYEOF'
import sys
sys.path.insert(0, '/usr/local/lib/hermes-agent')
from hermes_cli.main import _write_web_ui_build_stamp, _workspace_root, _web_ui_build_needed, _compute_web_ui_content_hash
from pathlib import Path
web_dir = Path('/usr/local/lib/hermes-agent/web')
project_root = _workspace_root(web_dir)
print(f'project_root={project_root}, web_dir={web_dir}')
# Check .gitignore exists
gitignore = project_root / '.gitignore'
print(f'.gitignore exists: {gitignore.exists()}')
# Check sentinel
dist_dir = project_root / "hermes_cli" / "web_dist"
sentinel = dist_dir / ".vite" / "manifest.json"
if not sentinel.exists():
    sentinel = dist_dir / "index.html"
print(f'sentinel ({sentinel}) exists: {sentinel.exists()}')
# Check stamp
from hermes_cli.main import _web_ui_stamp_path
stamp_path = _web_ui_stamp_path()
print(f'stamp_path: {stamp_path}')
print(f'stamp exists: {stamp_path.exists()}')
if stamp_path.exists():
    import json
    stamp_data = json.loads(stamp_path.read_text())
    print(f'stamp contentHash: {stamp_data.get("contentHash")}')
    # Compute current hash
    current_hash = _compute_web_ui_content_hash(project_root, web_dir)
    print(f'current contentHash: {current_hash}')
    print(f'hash match: {stamp_data.get("contentHash") == current_hash}')
# Check build_needed
needed = _web_ui_build_needed(web_dir)
print(f'_web_ui_build_needed: {needed}')
_write_web_ui_build_stamp(project_root, web_dir)
print('Stamp written')
PYEOF

# Retry trigger: 2026-08-15T05:00:00Z

# Install ModelRelay and start automatically in the background
ARG MODELRELAY_VERSION
# RUN npm install -g modelrelay@${MODELRELAY_VERSION} && \
RUN npm install -g github:gitricko/modelrelay && \
    npm cache clean --force

# Install OmniRoute and start automatically when desktop loads
ARG OMNIROUTE_VERSION
RUN npm install -g omniroute@${OMNIROUTE_VERSION} && \
    npm cache clean --force && \
    mkdir -p /usr/local/lib/node_modules/omniroute/app/logs/application

# Install code-server and start automatically when desktop loads
ARG CODE_SERVER_VERSION
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version=${CODE_SERVER_VERSION} --method=standalone --prefix=/usr/local && \
    ln -fs /usr/local/lib/code-server-${CODE_SERVER_VERSION} /usr/local/lib/code-server && \
    ln -fs /usr/local/lib/code-server/bin/code-server /usr/local/bin/code && \
    rm -rf ~/.cache
# Uncomment this when you want to use your own default.conf to route from your reverse proxy to code-server.  I rather use codeserver to route to WebTop port 3000
#    COPY default.conf /defaults/default.conf

# Switch to the abc user and set zsh as the default shell for both root and abc
RUN usermod -s $(which zsh) root; usermod -s $(which zsh) abc

# Install TailScale
RUN mkdir -p /var/run/tailscale /var/lib/tailscale && curl -fsSL https://tailscale.com/install.sh | sh && rm -rf /var/lib/apt/lists/*

# Install mnemon
ARG MNEMON_VERSION
ARG TARGETARCH
RUN echo "Building for architecture: $TARGETARCH"
RUN set -eux; \
    MNEMON_ARCH="${MNEMON_ARCH:-${TARGETARCH:-amd64}}"; \
    case "${MNEMON_ARCH}" in \
      amd64|x86_64) MNEMON_ARCH=amd64 ;; \
      arm64|aarch64) MNEMON_ARCH=arm64 ;; \
      *) echo "Unsupported MNEMON_ARCH: ${MNEMON_ARCH}" >&2; exit 1 ;; \
    esac; \
    curl -sL "https://github.com/mnemon-dev/mnemon/releases/download/v${MNEMON_VERSION}/mnemon_${MNEMON_VERSION}_linux_${MNEMON_ARCH}.tar.gz" -o /tmp/mnemon.tar.gz && \
    tar xzf /tmp/mnemon.tar.gz -C /tmp && \
    cp /tmp/mnemon /usr/local/bin/mnemon && \
    chmod +x /usr/local/bin/mnemon && \
    rm -rf /tmp/mnemon.tar.gz /tmp/mnemon

EXPOSE 8888 3000
