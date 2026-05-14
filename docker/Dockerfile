ARG HERMES_VERSION="v2026.5.7"
ARG OMNIROUTE_VERSION=3.7.7
ARG MODELRELAY_VERSION=1.17.1
ARG OLLAMA_VERSION=0.21.0
ARG NODE_VERSION=24
ARG CODE_SERVER_VERSION=4.118.0
ARG MNEMON_VERSION=0.1.3
ARG TARGETARCH

# Use the official Ollama image to get the binary
FROM ollama/ollama:${OLLAMA_VERSION} AS ollama-bin

# Get the binaries from official Node image
FROM node:${NODE_VERSION}-slim AS node-bin

# Use your preferred Webtop flavor as the base (e.g., Ubuntu, Alpine)
FROM lscr.io/linuxserver/webtop:ubuntu-mate

# Install help utilities and clean up apt cache to reduce image size
RUN apt-get update && apt-get install -y htop zsh ripgrep && rm -rf /var/lib/apt/lists/*

# Copy Node.js binaries and libraries
COPY --from=node-bin --chown=abc:abc /usr/local/bin/node /usr/local/bin/
COPY --from=node-bin --chown=abc:abc /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm

# Copy the Ollama binary from the official image
COPY --from=ollama-bin --chown=abc:abc /usr/bin/ollama /usr/local/bin/ollama

# Start desktop launchers and bootstrap scripts automatically when the desktop loads
RUN mkdir -p /custom-cont-init.d
COPY --chown=abc:abc *.desktop /custom-cont-init.d
COPY --chown=abc:abc *.sh /custom-cont-init.d

# Install Hermes
ARG HERMES_VERSION
RUN curl -fsSL "https://raw.githubusercontent.com/NousResearch/hermes-agent/${HERMES_VERSION}/scripts/install.sh" | bash -s -- --skip-setup && \
    npm cache clean --force && \
    rm -rf /var/lib/apt/lists/* && \
    chown abc:abc -R /usr/local/lib/hermes-agent

# Install ModelRelay and start automatically when desktop loads
ARG MODELRELAY_VERSION
RUN npm install -g modelrelay@${MODELRELAY_VERSION} && \
    npm cache clean --force && \
    chown abc:abc -R /usr/local/lib/node_modules/modelrelay /usr/local/bin/modelrelay

# Install OmniRoute and start automatically when desktop loads
ARG OMNIROUTE_VERSION
RUN npm install -g omniroute@${OMNIROUTE_VERSION} && \
    npm cache clean --force && \
    mkdir -p /usr/local/lib/node_modules/omniroute/app/logs/application && \
    chown abc:abc -R /usr/local/lib/node_modules/omniroute /usr/local/bin/omniroute

# Install code-server and start automatically when desktop loads
ARG CODE_SERVER_VERSION
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version=${CODE_SERVER_VERSION} --method=standalone --prefix=/usr/local && \
    ln -fs /usr/local/lib/code-server-${CODE_SERVER_VERSION} /usr/local/lib/code-server && \
    ln -fs /usr/local/lib/code-server/bin/code-server /usr/local/bin/code && \
    rm -rf ~/.cache
COPY default.conf /defaults/default.conf

# Switch to the abc user and set zsh as the default shell for both root and abc
RUN usermod -s $(which zsh) root; usermod -s $(which zsh) abc

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

EXPOSE 8888
