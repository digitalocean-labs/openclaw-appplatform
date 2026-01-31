FROM tailscale/tailscale:stable AS tailscale

FROM ubuntu:noble

# Use bash for the shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Copy Tailscale binaries
# real_tailscale is used because the rootfs/usr/local/bin/tailscale script is a wrapper that injects the socket path for tailscale CLI
COPY --from=tailscale /usr/local/bin/tailscale /usr/local/bin/real_tailscale
COPY --from=tailscale /usr/local/bin/tailscaled /usr/local/bin/tailscaled
COPY --from=tailscale /usr/local/bin/containerboot /usr/local/bin/containerboot

ARG TARGETARCH=amd64
ARG MOLTBOT_VERSION=2026.1.27-beta.1
ARG S6_OVERLAY_VERSION=3.2.1.0
ARG NODE_MAJOR=24
ARG RESTIC_VERSION=0.17.3
ARG NGROK_VERSION=3
ARG YQ_VERSION=4.44.3
ARG NVM_VERSION=0.40.4
ARG MOLTBOT_STATE_DIR=/data/.moltbot
ARG MOLTBOT_WORKSPACE_DIR=/data/workspace

ENV MOLTBOT_STATE_DIR=${MOLTBOT_STATE_DIR}
ENV MOLTBOT_WORKSPACE_DIR=${MOLTBOT_WORKSPACE_DIR}
ENV NODE_ENV=production
ENV DEBIAN_FRONTEND=noninteractive
ENV S6_KEEP_ENV=1
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0

# Install OS deps + Node.js + sshd + restic + s6-overlay
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      wget \
      unzip \
      vim \
      curl \
      git \
      gh \
      gnupg \
      ssh-import-id \
      openssl \
      jq \
      sudo \
      git \
      bzip2 \
      openssh-server \
      cron \
      build-essential \
      procps \
      xz-utils; \
    # Install restic
    RESTIC_ARCH="$( [ "$TARGETARCH" = "arm64" ] && echo arm64 || echo amd64 )"; \
    wget -q -O /tmp/restic.bz2 \
      https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_${RESTIC_ARCH}.bz2; \
    bunzip2 /tmp/restic.bz2; \
    mv /tmp/restic /usr/local/bin/restic; \
    chmod +x /usr/local/bin/restic; \
    # Install ngrok
    mkdir -p /etc/apt/keyrings; \
    curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
      | gpg --dearmor -o /etc/apt/keyrings/ngrok.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/ngrok.gpg] https://ngrok-agent.s3.amazonaws.com buster main" \
      > /etc/apt/sources.list.d/ngrok.list; \
    apt-get update && apt-get install -y ngrok; \
    # Install yq for YAML parsing
    YQ_ARCH="$( [ "$TARGETARCH" = "arm64" ] && echo arm64 || echo amd64 )"; \
    wget -q -O /usr/local/bin/yq \
      https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${YQ_ARCH}; \
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

# Apply rootfs overlay early - allows user creation to use existing home directories
COPY rootfs/ /

# Create non-root user (using existing home directory from rootfs)
RUN useradd -d /home/moltbot -s /bin/bash moltbot \
    && mkdir -p "${MOLTBOT_STATE_DIR}" "${MOLTBOT_WORKSPACE_DIR}" \
    && ln -s ${MOLTBOT_STATE_DIR} /home/moltbot/.clawdbot \
    && chown -R moltbot:moltbot /data \
    && chown -R moltbot:moltbot /home/moltbot

# nvm and pnpm paths
ENV NVM_DIR="/home/moltbot/.nvm"
ENV PNPM_HOME="/home/moltbot/.local/share/pnpm"
ENV PATH="${PNPM_HOME}:${PATH}"

# Create directories
RUN mkdir -p ${PNPM_HOME} && chown -R moltbot:moltbot /home/moltbot/.local

USER moltbot

# Install Homebrew (Linuxbrew) - must be done as non-root user
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true

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

RUN echo "export MOLTBOT_STATE_DIR=${MOLTBOT_STATE_DIR}" >> /home/moltbot/.bashrc
RUN echo "export MOLTBOT_WORKSPACE_DIR=${MOLTBOT_WORKSPACE_DIR}" >> /home/moltbot/.bashrc
# Switch back to root for final setup
USER root

# Fix ownership for any files in home directories (in case ubuntu user exists)
RUN if [ -d /home/ubuntu ]; then chown -R ubuntu:ubuntu /home/ubuntu; fi

# Generate initial package selections list (for restore capability)
RUN dpkg --get-selections > /etc/moltbot/dpkg-selections


# s6-overlay init (must run as root, services drop privileges as needed)
ENTRYPOINT ["/init"]
