#!/bin/bash
# Test: Persistence with DigitalOcean Spaces
# Verifies that backup service starts and data persists across container restarts
#
# Prerequisites (handled by CI workflow):
# - Spaces bucket created and credentials injected into .env
# - Container started with persistence configuration

set -e

CONTAINER=${1:?Usage: $0 <container-name>}
source "$(dirname "$0")/../lib.sh"

# Helper to run commands with restic environment loaded
run_with_restic_env() {
    docker exec "$CONTAINER" bash -c "source /etc/s6-overlay/lib/env-utils.sh && source_env_prefix RESTIC_ && $*"
}

echo "Testing persistence-enabled configuration (container: $CONTAINER)..."

# Container should be running
docker exec "$CONTAINER" true || { echo "error: container not responsive"; exit 1; }

# Check if persistence is actually configured (CI may skip if no credentials)
if ! docker exec "$CONTAINER" test -f /run/s6/container_environment/RESTIC_SPACES_BUCKET 2>/dev/null; then
    echo "SKIP: Persistence not configured (RESTIC_SPACES_BUCKET not set)"
    echo "Set DO_SPACES_ACCESS_KEY_ID and DO_SPACES_SECRET_ACCESS_KEY secrets to enable"
    exit 0
fi

# Wait for backup service to be ready
wait_for_service "$CONTAINER" "backup" || exit 1

# Verify restic repository is initialized
if ! run_with_restic_env "restic snapshots --latest 1" >/dev/null 2>&1; then
    echo "error: Restic repository not initialized"
    exit 1
fi
echo "✓ Restic repository initialized"

# Create test data
TEST_CONTENT="persistence-test-$(date +%s)"
TEST_FILE="/data/.openclaw/test-persistence.txt"
docker exec "$CONTAINER" bash -c "echo '$TEST_CONTENT' > '$TEST_FILE'"
echo "✓ Test data created"

# Trigger a backup
if ! docker exec "$CONTAINER" /usr/local/bin/restic-backup; then
    echo "error: Backup failed"
    exit 1
fi
echo "✓ Backup completed"

# Verify snapshot was created
SNAPSHOT_COUNT=$(run_with_restic_env "restic snapshots --json" 2>/dev/null | jq length)
if [ "$SNAPSHOT_COUNT" -lt 1 ]; then
    echo "error: No snapshots found after backup"
    exit 1
fi
echo "✓ Snapshot created ($SNAPSHOT_COUNT total)"

# Restart container to test restore
restart_container "$CONTAINER"

# Wait for init scripts to complete by waiting for backup service to be ready
if ! wait_for_service "$CONTAINER" "backup"; then
    echo "--- Debug: Container logs after failed restart ---"
    docker logs "$CONTAINER" 2>&1 | tail -50
    echo "---"
    echo "error: Backup service not ready after restart"
    exit 1
fi

# Verify test data was restored
RESTORED_CONTENT=$(docker exec "$CONTAINER" cat "$TEST_FILE" 2>/dev/null || echo "")
if [ "$RESTORED_CONTENT" != "$TEST_CONTENT" ]; then
    echo "error: Test data not restored correctly"
    echo "  Expected: $TEST_CONTENT"
    echo "  Got: $RESTORED_CONTENT"
    docker exec "$CONTAINER" ls -la /data/.openclaw/ 2>/dev/null || true
    exit 1
fi
echo "✓ Test data restored successfully"

echo "persistence-enabled tests passed"
