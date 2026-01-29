FROM tailscale/tailscale:stable AS tailscale

FROM ubuntu:noble

# Copy Tailscale binaries
COPY --from=tailscale /usr/local/bin/tailscale /usr/local/bin/real_tailscale
COPY --from=tailscale /usr/local/bin/tailscaled /usr/local/bin/tailscaled
COPY --from=tailscale /usr/local/bin/containerboot /usr/local/bin/containerboot
COPY tailscale /usr/local/bin/tailscale

ARG TARGETARCH
ARG CLAWDBOT_VERSION=latest
ARG LITESTREAM_VERSION=0.5.6
ARG NODE_MAJOR=24

ENV CLAWDBOT_STATE_DIR=/data/.clawdbot \
    CLAWDBOT_WORKSPACE_DIR=/data/workspace \
    TS_STATE_DIR=/data/tailscale \
    NODE_ENV=production \
    DEBIAN_FRONTEND=noninteractive

# Install OS deps + Node.js + sshd + Litestream + s3cmd
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      wget \
      curl \
      gnupg \
      openssl \
      jq \
      sudo \
      git \
      s3cmd \
      python3 \
      openssh-server; \
    # Install Node.js from NodeSource
    mkdir -p /etc/apt/keyrings; \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" > /etc/apt/sources.list.d/nodesource.list; \
    apt-get update; \
    apt-get install -y nodejs; \
    # Install Litestream
    LITESTREAM_ARCH="$( [ "$TARGETARCH" = "arm64" ] && echo arm64 || echo x86_64 )"; \
    wget -O /tmp/litestream.deb \
      https://github.com/benbjohnson/litestream/releases/download/v${LITESTREAM_VERSION}/litestream-${LITESTREAM_VERSION}-linux-${LITESTREAM_ARCH}.deb; \
    dpkg -i /tmp/litestream.deb; \
    rm /tmp/litestream.deb; \
    # Setup SSH
    mkdir -p /run/sshd; \
    # Cleanup
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Copy configuration files
COPY entrypoint.sh /entrypoint.sh
COPY litestream.yml /etc/litestream.yml
COPY moltbot.default.json /etc/clawdbot/moltbot.default.json
COPY configs/ssh_config.d/ /etc/ssh/ssh_config.d/
COPY configs/sshd_config.d/ /etc/ssh/sshd_config.d/
RUN chmod +x /entrypoint.sh

# Create non-root user with sudo access and SSH capability
RUN useradd -m -d /home/clawdbot -s /bin/bash clawdbot \
    && mkdir -p "${CLAWDBOT_STATE_DIR}" "${CLAWDBOT_WORKSPACE_DIR}" "${TS_STATE_DIR}" \
    && chown -R clawdbot:clawdbot /data \
    && echo 'clawdbot ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/clawdbot \
    && chmod 440 /etc/sudoers.d/clawdbot \
    && mkdir -p /home/clawdbot/.ssh \
    && chmod 700 /home/clawdbot/.ssh \
    && chown clawdbot:clawdbot /home/clawdbot/.ssh

# Homebrew and pnpm paths
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"
ENV PNPM_HOME="/home/clawdbot/.local/share/pnpm"
ENV PATH="${PNPM_HOME}:${PATH}"

# Create pnpm directory
RUN mkdir -p ${PNPM_HOME} && chown -R clawdbot:clawdbot /home/clawdbot/.local

USER clawdbot

# Install Homebrew (must run as non-root)
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install pnpm and clawdbot
RUN brew install pnpm \
    && pnpm add -g "clawdbot@${CLAWDBOT_VERSION}"

# Expose ports: 8080 for LAN mode, 22 for SSH
EXPOSE 8080 22

ENTRYPOINT ["/entrypoint.sh"]
