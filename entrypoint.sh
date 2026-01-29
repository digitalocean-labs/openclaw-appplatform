#!/bin/bash
set -e

# Ensure directories exist
mkdir -p "$CLAWDBOT_STATE_DIR" "$CLAWDBOT_WORKSPACE_DIR" "$CLAWDBOT_STATE_DIR/memory"

# Configure s3cmd for DO Spaces
configure_s3cmd() {
  cat > /tmp/.s3cfg << EOF
[default]
access_key = ${LITESTREAM_ACCESS_KEY_ID}
secret_key = ${LITESTREAM_SECRET_ACCESS_KEY}
host_base = ${SPACES_ENDPOINT}
host_bucket = %(bucket)s.${SPACES_ENDPOINT}
use_https = True
EOF
}

# Restore from Spaces backup if configured
if [ -n "$LITESTREAM_ACCESS_KEY_ID" ] && [ -n "$SPACES_BUCKET" ]; then
  echo "Restoring state from Spaces backup..."
  configure_s3cmd

  # Restore JSON state files (config, devices, sessions) via tar
  STATE_BACKUP_PATH="s3://${SPACES_BUCKET}/clawdbot/state-backup.tar.gz"
  if s3cmd -c /tmp/.s3cfg ls "$STATE_BACKUP_PATH" 2>/dev/null | grep -q state-backup; then
    echo "Downloading state backup..."
    s3cmd -c /tmp/.s3cfg get "$STATE_BACKUP_PATH" /tmp/state-backup.tar.gz && \
      tar -xzf /tmp/state-backup.tar.gz -C "$CLAWDBOT_STATE_DIR" || \
      echo "Warning: failed to restore state backup (continuing)"
    rm -f /tmp/state-backup.tar.gz
  else
    echo "No state backup found (first deployment)"
  fi

  # Restore SQLite memory database via Litestream
  echo "Restoring SQLite from Litestream..."
  litestream restore -if-replica-exists -config /etc/litestream.yml \
    "$CLAWDBOT_STATE_DIR/memory/main.sqlite" || true
fi

# Show version
echo "Clawdbot version: $(clawdbot --version 2>/dev/null || echo 'unknown')"

# Generate a gateway token if not provided
if [ -z "$CLAWDBOT_GATEWAY_TOKEN" ]; then
  export CLAWDBOT_GATEWAY_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '=/+' | head -c 32)
  echo "Generated gateway token (ephemeral)"
fi

# Build config file dynamically based on environment variables
# This allows flexibility without requiring CLI parameters
CONFIG_FILE="$CLAWDBOT_STATE_DIR/clawdbot.json"

echo "Building config: $CONFIG_FILE"

# Determine gateway mode: tailscale (default) or lan
GATEWAY_MODE="${CLAWDBOT_GATEWAY_MODE:-tailscale}"

# Start with base config
if [ "$GATEWAY_MODE" = "tailscale" ]; then
  echo "Gateway mode: Tailscale"
  cat > "$CONFIG_FILE" << CONFIGEOF
{
  "gateway": {
    "mode": "local",
    "bind": "loopback",
    "tailscale": { "mode": "serve" },
    "auth": {
      "allowTailscale": true
    },
    "controlUi": {
      "allowInsecureAuth": true
    }
  }
}
CONFIGEOF
else
  # LAN mode - bind to all interfaces with trusted proxies for App Platform/Cloudflare
  PORT="${PORT:-8080}"
  echo "Gateway mode: LAN (port $PORT)"
  
  # Determine auth config based on SETUP_PASSWORD
  if [ -n "$SETUP_PASSWORD" ]; then
    AUTH_CONFIG='"mode": "password"'
    echo "Auth: password"
  else
    AUTH_CONFIG='"mode": "token"'
    echo "Auth: token"
  fi

  cat > "$CONFIG_FILE" << CONFIGEOF
{
  "gateway": {
    "mode": "local",
    "port": $PORT,
    "bind": "lan",
    "trustedProxies": ["0.0.0.0/0", "::/0"],
    "auth": {
      $AUTH_CONFIG
    },
    "controlUi": {
      "allowInsecureAuth": true
    }
  }
}
CONFIGEOF
fi

# Add Gradient AI provider if API key is set
if [ -n "$GRADIENT_API_KEY" ]; then
  echo "Adding Gradient AI provider to config"
  GRADIENT_CONFIG=$(cat << 'GRADIENTEOF'
{
  "models": {
    "mode": "merge",
    "providers": {
      "gradient": {
        "baseUrl": "https://inference.do-ai.run/v1",
        "api": "openai-completions",
        "models": [
          {
            "id": "llama3.3-70b-instruct",
            "name": "Llama 3.3 70B Instruct",
            "reasoning": false,
            "input": ["text"],
            "contextWindow": 128000,
            "maxTokens": 8192
          },
          {
            "id": "anthropic-claude-4.5-sonnet",
            "name": "Claude 4.5 Sonnet",
            "reasoning": false,
            "input": ["text"],
            "contextWindow": 200000,
            "maxTokens": 8192
          },
          {
            "id": "anthropic-claude-opus-4.5",
            "name": "Claude Opus 4.5",
            "reasoning": true,
            "input": ["text"],
            "contextWindow": 200000,
            "maxTokens": 16384
          },
          {
            "id": "deepseek-r1-distill-llama-70b",
            "name": "DeepSeek R1 Distill Llama 70B",
            "reasoning": true,
            "input": ["text"],
            "contextWindow": 128000,
            "maxTokens": 8192
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "gradient/llama3.3-70b-instruct"
      }
    }
  }
}
GRADIENTEOF
)
  # Merge Gradient config into main config, injecting the API key
  jq --argjson gradient "$GRADIENT_CONFIG" \
     --arg apiKey "$GRADIENT_API_KEY" \
     '. * $gradient | .models.providers.gradient.apiKey = $apiKey' \
     "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
fi

# Backup function for JSON state files
backup_state() {
  if [ -n "$LITESTREAM_ACCESS_KEY_ID" ] && [ -n "$SPACES_BUCKET" ]; then
    echo "Backing up state to Spaces..."
    cd "$CLAWDBOT_STATE_DIR"
    # Backup JSON files (exclude memory/ which Litestream handles)
    tar -czf /tmp/state-backup.tar.gz \
      --exclude='memory' \
      --exclude='*.sqlite*' \
      --exclude='*.db*' \
      --exclude='gateway.*.lock' \
      . 2>/dev/null || true

    # Upload to Spaces using s3cmd
    if [ -f /tmp/state-backup.tar.gz ]; then
      s3cmd -c /tmp/.s3cfg put /tmp/state-backup.tar.gz \
        "s3://${SPACES_BUCKET}/clawdbot/state-backup.tar.gz" && \
        echo "State backup uploaded" || \
        echo "Warning: state backup upload failed"
      rm -f /tmp/state-backup.tar.gz
    fi
  fi
}

# Background backup loop (every 5 minutes)
start_backup_loop() {
  while true; do
    sleep 300
    backup_state
  done
}

# Graceful shutdown handler
shutdown_handler() {
  echo "Shutting down, saving state..."
  backup_state
  exit 0
}
trap shutdown_handler SIGTERM SIGINT

# Start Tailscale if in tailscale mode
if [ "$GATEWAY_MODE" = "tailscale" ]; then
  echo "Starting Tailscale daemon..."
  /usr/local/bin/containerboot &
fi

# Start gateway - all configuration is in the config file
echo "Starting clawdbot gateway..."
if [ -n "$LITESTREAM_ACCESS_KEY_ID" ] && [ -n "$SPACES_BUCKET" ]; then
  echo "Mode: Litestream + state backup enabled"

  # Start periodic backup in background
  start_backup_loop &

  # Run gateway with Litestream for SQLite replication
  litestream replicate -config /etc/litestream.yml \
    -exec "clawdbot gateway --allow-unconfigured" &
  GATEWAY_PID=$!

  # Wait for gateway and handle shutdown
  wait $GATEWAY_PID
else
  echo "Mode: ephemeral (no persistence)"
  exec clawdbot gateway --allow-unconfigured
fi
