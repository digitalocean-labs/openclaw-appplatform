#!/bin/bash
# Test: SSH disable and restart
# Verifies SSH can be disabled via env var and service restart

set -e

CONTAINER=${1:?Usage: $0 <container-name>}
source "$(dirname "$0")/../lib.sh"

echo "Testing SSH disable/restart (container: $CONTAINER)..."

# Container should be running
docker exec "$CONTAINER" true || { echo "error: container not responsive"; exit 1; }

# Wait for SSH to be ready (container just started)
wait_for_service "$CONTAINER" "sshd" || exit 1
echo "✓ SSH initially running"

# Disable SSH by updating the s6 environment variable
docker exec "$CONTAINER" bash -c "echo 'false' > /run/s6/container_environment/SSH_ENABLE"
echo "✓ Set SSH_ENABLE=false"

# Gracefully restart sshd service (sends SIGTERM, waits, then restarts)
docker exec "$CONTAINER" /command/s6-svc -r /run/service/sshd
sleep 2
echo "✓ Restarted sshd service"

# SSH should now be down (service exits when SSH_ENABLE=false)
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

# Re-enable SSH
docker exec "$CONTAINER" bash -c "echo 'true' > /run/s6/container_environment/SSH_ENABLE"
echo "✓ Set SSH_ENABLE=true"

# Restart sshd service
docker exec "$CONTAINER" /command/s6-svc -u /run/service/sshd
sleep 2
echo "✓ Started sshd service"

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
