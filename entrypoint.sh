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

# Start with or without Litestream replication
# Use same command format as fly.toml: gateway --allow-unconfigured --port X --bind lan
if [ -n "$LITESTREAM_ACCESS_KEY_ID" ] && [ -n "$SPACES_BUCKET" ]; then
  echo "Mode: Litestream + state backup enabled"

  # Start periodic backup in background
  start_backup_loop &

  # Run gateway with Litestream for SQLite replication
  litestream replicate -config /etc/litestream.yml \
    -exec "clawdbot gateway --allow-unconfigured --port $PORT --bind lan --token $CLAWDBOT_GATEWAY_TOKEN" &
  GATEWAY_PID=$!

  # Wait for gateway and handle shutdown
  wait $GATEWAY_PID
else
  echo "Mode: ephemeral (no persistence)"
  exec clawdbot gateway --allow-unconfigured --port "$PORT" --bind lan --token "$CLAWDBOT_GATEWAY_TOKEN"
fi
