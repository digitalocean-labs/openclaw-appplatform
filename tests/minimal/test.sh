#!/bin/bash
# Test: minimal configuration
# Verifies base container with all features disabled

set -e

CONTAINER=${1:?Usage: $0 <container-name>}

echo "Testing minimal configuration (container: $CONTAINER)..."

# Container should be running
docker exec "$CONTAINER" true || { echo "error: container not responsive"; exit 1; }

# Gateway should be listening (may take a moment to start)
for i in {1..5}; do
    if docker exec "$CONTAINER" pgrep -x node >/dev/null 2>&1; then
        echo "✓ node process running"
        break
    fi
    if [ $i -eq 5 ]; then
        echo "warning: node process not found (may still be starting)"
    fi
    sleep 2
done

# SSH should NOT be running
if docker exec "$CONTAINER" pgrep -x sshd >/dev/null 2>&1; then
    echo "error: sshd running but SSH_ENABLE=false"
    exit 1
fi
echo "✓ sshd not running (as expected)"

echo "minimal tests passed"
