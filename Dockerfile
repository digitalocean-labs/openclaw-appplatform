FROM tailscale/tailscale:stable AS tailscale

FROM ubuntu:noble

# Copy Tailscale binaries
# real_tailscale is used because the rootfs/usr/local/bin/tailscale script is a wrapper that injects the socket path for tailscale CLI
COPY --from=tailscale /usr/local/bin/tailscale /usr/local/bin/real_tailscale
COPY --from=tailscale /usr/local/bin/tailscaled /usr/local/bin/tailscaled
COPY --from=tailscale /usr/local/bin/containerboot /usr/local/bin/containerboot

ARG TARGETARCH
ARG MOLTBOT_VERSION=2026.1.27-beta.1
ARG LITESTREAM_VERSION=0.5.6
ARG S6_OVERLAY_VERSION=3.2.1.0
ARG NODE_MAJOR=24

ENV MOLTBOT_STATE_DIR=/data/.moltbot \
    MOLTBOT_WORKSPACE_DIR=/data/workspace \
    TS_STATE_DIR=/data/tailscale \
    NODE_ENV=production \
    DEBIAN_FRONTEND=noninteractive \
    S6_KEEP_ENV=1 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0

# Install OS deps + Node.js + sshd + Litestream + restic + s6-overlay
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      wget \
      curl \
      gnupg \
      ssh-import-id \
      openssl \
      jq \
      sudo \
      git \
      bzip2 \
      openssh-server \
      cron \
      xz-utils; \
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
    # Install restic
    RESTIC_ARCH="$( [ "$TARGETARCH" = "arm64" ] && echo arm64 || echo amd64 )"; \
    wget -q -O /tmp/restic.bz2 \
      https://github.com/restic/restic/releases/download/v0.17.3/restic_0.17.3_linux_${RESTIC_ARCH}.bz2; \
    bunzip2 /tmp/restic.bz2; \
    mv /tmp/restic /usr/local/bin/restic; \
    chmod +x /usr/local/bin/restic; \
    # Install yq for YAML parsing
    YQ_ARCH="$( [ "$TARGETARCH" = "arm64" ] && echo arm64 || echo amd64 )"; \
    wget -q -O /usr/local/bin/yq \
      https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_${YQ_ARCH}; \
    chmod +x /usr/local/bin/yq; \
    # Install s6-overlay
    S6_ARCH="$( [ "$TARGETARCH" = "arm64" ] && echo aarch64 || echo x86_64 )"; \
    wget -O /tmp/s6-overlay-noarch.tar.xz \
      https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz; \
    wget -O /tmp/s6-overlay-arch.tar.xz \
      https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz; \
    tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz; \
    rm /tmp/s6-overlay-*.tar.xz; \
    # Setup SSH
    mkdir -p /run/sshd; \
    # Cleanup
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Create non-root user with sudo access and SSH capability
RUN useradd -m -d /home/moltbot -s /bin/bash moltbot \
    && mkdir -p "${MOLTBOT_STATE_DIR}" "${MOLTBOT_WORKSPACE_DIR}" "${TS_STATE_DIR}" \
    && chown -R moltbot:moltbot /data \
    && echo 'moltbot ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/moltbot \
    && chmod 440 /etc/sudoers.d/moltbot \
    && mkdir -p /home/moltbot/.ssh \
    && chmod 700 /home/moltbot/.ssh \
    && chown moltbot:moltbot /home/moltbot/.ssh \
    # Setup ubuntu user for SSH
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
    && chmod 440 /etc/sudoers.d/ubuntu \
    && mkdir -p /home/ubuntu/.ssh \
    && chmod 700 /home/ubuntu/.ssh \
    && chown ubuntu:ubuntu /home/ubuntu/.ssh

# Create pnpm directory
RUN mkdir -p /home/moltbot/.local/share/pnpm && chown -R moltbot:moltbot /home/moltbot/.local

USER moltbot

# Install nvm, Node.js LTS, pnpm, and moltbot
RUN export SHELL=/bin/bash  && export NVM_DIR="$HOME/.nvm" \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash \
    && . "$NVM_DIR/nvm.sh" \
    && nvm install --lts \
    && nvm use --lts \
    && nvm alias default lts/* \
    && npm install -g pnpm \
    && pnpm setup \
    && export PNPM_HOME="/home/moltbot/.local/share/pnpm" \
    && export PATH="$PNPM_HOME:$PATH" \
    && pnpm add -g "moltbot@${MOLTBOT_VERSION}"

# Switch back to root for final overlay
USER root

# Apply rootfs overlay - allows users to add/override any files
# This is done last so user customizations take precedence
COPY rootfs/ /

# Fix ownership for any files copied to moltbot's home
RUN chown -R moltbot:moltbot /home/moltbot
RUN chown -R ubuntu:ubuntu /home/ubuntu

# Generate initial package selections list (for restore capability)
RUN dpkg --get-selections > /etc/moltbot/dpkg-selections


# s6-overlay init (must run as root, services drop privileges as needed)
ENTRYPOINT ["/init"]
