FROM node:24-slim

ARG TARGETARCH
ARG CLAWDBOT_VERSION=latest
ARG LITESTREAM_VERSION=0.5.6

ENV PORT=8080 \
    CLAWDBOT_STATE_DIR=/data/.clawdbot \
    CLAWDBOT_WORKSPACE_DIR=/data/workspace \
    NODE_ENV=production

# Install OS deps + Litestream
# Note: Litestream 0.5.x uses x86_64 (not amd64) and no 'v' prefix in filename
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        git; \
    LITESTREAM_ARCH="$( [ "$TARGETARCH" = "arm64" ] && echo arm64 || echo x86_64 )"; \
    wget -O /tmp/litestream.deb \
      https://github.com/benbjohnson/litestream/releases/download/v${LITESTREAM_VERSION}/litestream-${LITESTREAM_VERSION}-linux-${LITESTREAM_ARCH}.deb; \
    dpkg -i /tmp/litestream.deb; \
    rm /tmp/litestream.deb; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Install Clawdbot
RUN npm install -g clawdbot@${CLAWDBOT_VERSION}

# Create non-root user
RUN useradd -r -u 10001 clawdbot \
    && mkdir -p /data/.clawdbot /data/workspace \
    && chown -R clawdbot:clawdbot /data

COPY entrypoint.sh /entrypoint.sh
COPY litestream.yml /etc/litestream.yml
RUN chmod +x /entrypoint.sh

EXPOSE 8080

USER clawdbot
ENTRYPOINT ["/entrypoint.sh"]
