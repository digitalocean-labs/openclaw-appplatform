#!/bin/bash
# Test: SSH enabled configuration
# Verifies SSH service starts correctly

set -e

CONTAINER=${1:?Usage: $0 <container-name>}

echo "Testing ssh-enabled configuration (container: $CONTAINER)..."

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

# SSH port should be listening
docker exec "$CONTAINER" ss -tlnp | grep -q ":22 " || { echo "error: SSH not listening on port 22"; exit 1; }
echo "✓ SSH listening on port 22"

# Authorized keys should be set up
docker exec "$CONTAINER" test -f /root/.ssh/authorized_keys || { echo "error: authorized_keys not found"; exit 1; }
echo "✓ authorized_keys exists"

echo "ssh-enabled tests passed"
