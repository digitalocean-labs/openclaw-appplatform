FROM tailscale/tailscale:stable AS tailscale

FROM ubuntu:noble

# Copy Tailscale binaries
COPY --from=tailscale /usr/local/bin/tailscale /usr/local/bin/real_tailscale
COPY --from=tailscale /usr/local/bin/tailscaled /usr/local/bin/tailscaled
COPY --from=tailscale /usr/local/bin/containerboot /usr/local/bin/containerboot
COPY tailscale /usr/local/bin/tailscale

ARG TARGETARCH
ARG MOLTBOT_VERSION=latest
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

# Install OS deps + Node.js + sshd + Litestream + s3cmd + s6-overlay
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
      openssh-server \
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
    && chown moltbot:moltbot /home/moltbot/.ssh

# Homebrew and pnpm paths
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"
ENV PNPM_HOME="/home/moltbot/.local/share/pnpm"
ENV PATH="${PNPM_HOME}:${PATH}"

# Create pnpm directory
RUN mkdir -p ${PNPM_HOME} && chown -R moltbot:moltbot /home/moltbot/.local

USER moltbot

# Install Homebrew (must run as non-root)
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install pnpm and moltbot
RUN brew install pnpm \
    && pnpm add -g "moltbot@${MOLTBOT_VERSION}"

# Switch back to root for final overlay
USER root

# Apply rootfs overlay - allows users to add/override any files
# This is done last so user customizations take precedence
COPY rootfs/ /

# Fix ownership for any files copied to moltbot's home
RUN chown -R moltbot:moltbot /home/moltbot 2>/dev/null || true

# Expose ports: 8080 for LAN mode, 22 for SSH
EXPOSE 8080 22

# s6-overlay init (must run as root, services drop privileges as needed)
ENTRYPOINT ["/init"]
