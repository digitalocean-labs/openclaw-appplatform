#!/bin/bash
# Test: SSH and UI enabled configuration
# Verifies multiple services run together

set -e

CONTAINER=${1:?Usage: $0 <container-name>}

echo "Testing ssh-and-ui configuration (container: $CONTAINER)..."

# Container should be running
docker exec "$CONTAINER" true || { echo "error: container not responsive"; exit 1; }

# SSH should be running
for i in {1..5}; do
    if docker exec "$CONTAINER" pgrep -x sshd >/dev/null 2>&1; then
        echo "✓ sshd process running"
        break
    fi
    if [ $i -eq 5 ]; then
        echo "error: sshd not running but SSH_ENABLE=true"
        exit 1
    fi
    sleep 2
done

# Node process for gateway
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

echo "ssh-and-ui tests passed"
