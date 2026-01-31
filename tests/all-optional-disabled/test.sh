#!/bin/bash
# Test: All optional features disabled
# Verifies explicit false values are handled correctly

set -e

CONTAINER=${1:?Usage: $0 <container-name>}

echo "Testing all-optional-disabled configuration (container: $CONTAINER)..."

# Container should be running
docker exec "$CONTAINER" true || { echo "error: container not responsive"; exit 1; }

# SSH should NOT be running
if docker exec "$CONTAINER" pgrep -x sshd >/dev/null 2>&1; then
    echo "error: sshd running but SSH_ENABLE=false"
    exit 1
fi
echo "✓ sshd not running (as expected)"

# Tailscale should NOT be running
if docker exec "$CONTAINER" pgrep -x tailscaled >/dev/null 2>&1; then
    echo "error: tailscaled running but TAILSCALE_ENABLE=false"
    exit 1
fi
echo "✓ tailscaled not running (as expected)"

# ngrok should NOT be running
if docker exec "$CONTAINER" pgrep -x ngrok >/dev/null 2>&1; then
    echo "error: ngrok running but ENABLE_NGROK=false"
    exit 1
fi
echo "✓ ngrok not running (as expected)"

echo "all-optional-disabled tests passed"
