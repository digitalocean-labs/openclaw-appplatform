#!/bin/bash
set -e

# Ensure directories exist
mkdir -p "$CLAWDBOT_STATE_DIR" "$CLAWDBOT_WORKSPACE_DIR"

# Restore from Litestream backup if configured
if [ -n "$LITESTREAM_ACCESS_KEY_ID" ] && [ -n "$SPACES_BUCKET" ]; then
  echo "Restoring from Litestream backup..."
  litestream restore -if-replica-exists -config /etc/litestream.yml \
    "$CLAWDBOT_STATE_DIR/memory.db" || true
fi

# Show version (image is rebuilt weekly with latest clawdbot)
echo "Clawdbot version: $(clawdbot --version 2>/dev/null || echo 'unknown')"

# Generate a gateway token if not provided (required for LAN binding)
if [ -z "$CLAWDBOT_GATEWAY_TOKEN" ]; then
  export CLAWDBOT_GATEWAY_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '=/+' | head -c 32)
  echo "Generated gateway token (ephemeral)"
fi

# Create config file for cloud deployment
# Note: Control UI device auth bypass requires clawdbot >= 2026.1.25
CONFIG_FILE="$CLAWDBOT_STATE_DIR/clawdbot.json"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Creating initial config: $CONFIG_FILE"
  cat > "$CONFIG_FILE" << 'CONFIGEOF'
{
  "gateway": {
    "mode": "local"
  }
}
CONFIGEOF
fi

PORT="${PORT:-8080}"
echo "Starting gateway: port=$PORT bind=lan"

# Start with or without Litestream replication
# Use same command format as fly.toml: gateway --allow-unconfigured --port X --bind lan
if [ -n "$LITESTREAM_ACCESS_KEY_ID" ] && [ -n "$SPACES_BUCKET" ]; then
  echo "Mode: Litestream replication enabled"
  exec litestream replicate -config /etc/litestream.yml \
    -exec "clawdbot gateway --allow-unconfigured --port $PORT --bind lan --token $CLAWDBOT_GATEWAY_TOKEN"
else
  echo "Mode: ephemeral (no persistence)"
  exec clawdbot gateway --allow-unconfigured --port "$PORT" --bind lan --token "$CLAWDBOT_GATEWAY_TOKEN"
fi
