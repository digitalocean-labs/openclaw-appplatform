#!/bin/bash
# Test: SSH authorized_keys setup
# Verifies SSH keys are properly configured

set -e

CONTAINER=${1:?Usage: $0 <container-name>}
source "$(dirname "$0")/../lib.sh"

echo "Testing SSH authorized_keys (container: $CONTAINER)..."

# Container should be running
docker exec "$CONTAINER" true || { echo "error: container not responsive"; exit 1; }

# Authorized keys should exist in ubuntu user's home
docker exec "$CONTAINER" test -f /home/ubuntu/.ssh/authorized_keys || { echo "error: authorized_keys not found"; exit 1; }
echo "✓ authorized_keys exists"

# .ssh directory should have correct permissions
SSH_DIR_PERMS=$(docker exec "$CONTAINER" stat -c %a /home/ubuntu/.ssh 2>/dev/null || echo "unknown")
if [ "$SSH_DIR_PERMS" != "700" ]; then
    echo "error: .ssh directory has wrong permissions: $SSH_DIR_PERMS (expected 700)"
    exit 1
fi
echo "✓ .ssh directory permissions correct (700)"

# authorized_keys should have correct permissions (600 per permissions.yaml)
AUTH_KEYS_PERMS=$(docker exec "$CONTAINER" stat -c %a /home/ubuntu/.ssh/authorized_keys 2>/dev/null || echo "unknown")
if [ "$AUTH_KEYS_PERMS" != "600" ]; then
    echo "error: authorized_keys has wrong permissions: $AUTH_KEYS_PERMS (expected 600)"
    exit 1
fi
echo "✓ authorized_keys permissions correct (600)"

# authorized_keys should not be empty
AUTH_KEYS_SIZE=$(docker exec "$CONTAINER" stat -c %s /home/ubuntu/.ssh/authorized_keys 2>/dev/null || echo "0")
if [ "$AUTH_KEYS_SIZE" = "0" ]; then
    echo "error: authorized_keys is empty"
    exit 1
fi
echo "✓ authorized_keys has content ($AUTH_KEYS_SIZE bytes)"

echo "SSH authorized_keys tests passed"
