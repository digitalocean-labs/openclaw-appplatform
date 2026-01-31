#!/bin/bash
# Test: UI disabled configuration
# Verifies gateway runs in CLI-only mode

set -e

CONTAINER=${1:?Usage: $0 <container-name>}

echo "Testing ui-disabled configuration (container: $CONTAINER)..."

# Container should be running
docker exec "$CONTAINER" true || { echo "error: container not responsive"; exit 1; }

# Gateway config should have ui disabled
docker exec "$CONTAINER" cat /data/.moltbot/moltbot.json | grep -q '"ui"' && {
    ui_enabled=$(docker exec "$CONTAINER" cat /data/.moltbot/moltbot.json | jq -r '.ui // false')
    if [ "$ui_enabled" = "true" ]; then
        echo "error: UI is enabled but ENABLE_UI=false"
        exit 1
    fi
}
echo "✓ UI disabled in config"

echo "ui-disabled tests passed"
