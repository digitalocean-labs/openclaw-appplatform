#!/bin/bash
# Test: SSH disable and restart
# Verifies SSH can be disabled via env var and container restart

set -e

CONTAINER=${1:?Usage: $0 <container-name>}
source "$(dirname "$0")/../lib.sh"

echo "Testing SSH disable/restart (container: $CONTAINER)..."

# Container should be running with SSH enabled
docker exec "$CONTAINER" true || { echo "error: container not responsive"; exit 1; }

# Wait for SSH to be ready
wait_for_service "$CONTAINER" "sshd" || exit 1
echo "✓ SSH initially running"

# Stop the container
docker compose stop
echo "✓ Container stopped"

# Disable SSH in .env
sed -i 's/^SSH_ENABLE=true/SSH_ENABLE=false/' .env
echo "✓ Set SSH_ENABLE=false in .env"

# Restart container with new environment
docker compose up -d
sleep 10
echo "✓ Container restarted"

# Container should be running
docker exec "$CONTAINER" true || { echo "error: container not responsive after restart"; exit 1; }

# SSH should now be down
assert_service_down "$CONTAINER" "sshd" || exit 1
echo "✓ SSH service is down after disable"

# sshd process should not be running
assert_process_not_running "$CONTAINER" "sshd" || exit 1
echo "✓ sshd process not running"

# Port 22 should not be listening
if docker exec "$CONTAINER" bash -c 'echo > /dev/tcp/127.0.0.1/22' 2>/dev/null; then
    echo "error: Port 22 still listening after SSH disabled"
    exit 1
fi
echo "✓ Port 22 not listening"

# Re-enable SSH in .env
sed -i 's/^SSH_ENABLE=false/SSH_ENABLE=true/' .env
echo "✓ Set SSH_ENABLE=true in .env"

# Restart container
docker compose stop
docker compose up -d
sleep 10
echo "✓ Container restarted"

# SSH should be back up
wait_for_service "$CONTAINER" "sshd" || exit 1
echo "✓ SSH service is up after re-enable"

# Port should be listening again
docker exec "$CONTAINER" bash -c 'echo > /dev/tcp/127.0.0.1/22' 2>/dev/null || {
    echo "error: SSH not listening on port 22 after re-enable"
    exit 1
}
echo "✓ Port 22 listening again"

echo "SSH disable/restart tests passed"
