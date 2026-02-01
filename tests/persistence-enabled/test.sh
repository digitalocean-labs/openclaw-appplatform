#!/bin/bash
# Test: Persistence with DigitalOcean Spaces
# Validates that data persists across container restarts using Restic backup/restore
#
# This test:
# 1. Creates a temporary DO Spaces bucket
# 2. Starts container with persistence enabled
# 3. Creates test data in backed-up paths
# 4. Triggers a backup
# 5. Stops and removes container
# 6. Starts a new container (simulating redeploy)
# 7. Verifies test data was restored
# 8. Cleans up the Spaces bucket
#
# Required environment variables (typically from CI secrets):
# - DO_SPACES_ACCESS_KEY_ID: Spaces access key
# - DO_SPACES_SECRET_ACCESS_KEY: Spaces secret key

set -e

CONTAINER=${1:?Usage: $0 <container-name>}
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

# Test configuration
SPACES_REGION="${SPACES_REGION:-sfo3}"
SPACES_ENDPOINT="${SPACES_REGION}.digitaloceanspaces.com"
BUCKET_NAME="openclaw-test-$(date +%s)-$$"
RESTIC_PASSWORD="test-password-$(date +%s)"
TEST_FILE_CONTENT="persistence-test-$(date +%s)"
TEST_FILE_PATH="/data/.openclaw/test-persistence.txt"

# s3cmd configuration
s3cmd_opts() {
    echo "--access_key=$DO_SPACES_ACCESS_KEY_ID"
    echo "--secret_key=$DO_SPACES_SECRET_ACCESS_KEY"
    echo "--host=$SPACES_ENDPOINT"
    echo "--host-bucket=%(bucket)s.$SPACES_ENDPOINT"
}

# Cleanup function
cleanup() {
    local exit_code=$?
    echo "Cleaning up..."

    # Stop the container first
    docker compose -f "$PROJECT_ROOT/compose.yaml" down 2>/dev/null || true

    # Remove the test bucket and its contents
    if [ -n "$BUCKET_NAME" ] && [ "$BUCKET_CREATED" = "true" ]; then
        echo "Deleting Spaces bucket: $BUCKET_NAME"
        # Delete bucket and all contents
        if ! s3cmd $(s3cmd_opts) rb --recursive "s3://$BUCKET_NAME" 2>/dev/null; then
            echo "warning: Could not delete bucket $BUCKET_NAME (may need manual cleanup)"
        fi
    fi

    exit $exit_code
}

BUCKET_CREATED="false"

# Check for required tools
check_prerequisites() {
    echo "Checking prerequisites..."

    if ! command -v s3cmd &>/dev/null; then
        echo "error: s3cmd not found. Install with: brew install s3cmd"
        exit 1
    fi

    # Check for required environment variables
    if [ -z "$DO_SPACES_ACCESS_KEY_ID" ] || [ -z "$DO_SPACES_SECRET_ACCESS_KEY" ]; then
        echo "SKIP: DO_SPACES_ACCESS_KEY_ID or DO_SPACES_SECRET_ACCESS_KEY not set"
        echo "Set these secrets in CI or export them locally to run persistence tests"
        exit 0
    fi

    echo "✓ Prerequisites met"
}

# Create a temporary Spaces bucket for testing
create_spaces_bucket() {
    echo "Creating temporary Spaces bucket: $BUCKET_NAME in $SPACES_REGION..."

    if ! s3cmd $(s3cmd_opts) mb "s3://$BUCKET_NAME"; then
        echo "error: Failed to create Spaces bucket"
        exit 1
    fi

    BUCKET_CREATED="true"
    echo "✓ Spaces bucket created: $BUCKET_NAME"
}

# Update container environment with Spaces configuration
configure_container_env() {
    echo "Configuring container with Spaces credentials..."

    # Create a new .env file with persistence settings
    cat > "$PROJECT_ROOT/.env" << EOF
# Persistence test configuration
TAILSCALE_ENABLE=false
ENABLE_NGROK=false
ENABLE_SPACES=true
SSH_ENABLE=false
ENABLE_UI=false
STABLE_HOSTNAME=$CONTAINER
S6_BEHAVIOUR_IF_STAGE2_FAILS=0

# Spaces configuration
RESTIC_SPACES_ACCESS_KEY_ID=$DO_SPACES_ACCESS_KEY_ID
RESTIC_SPACES_SECRET_ACCESS_KEY=$DO_SPACES_SECRET_ACCESS_KEY
RESTIC_SPACES_ENDPOINT=$SPACES_ENDPOINT
RESTIC_SPACES_BUCKET=$BUCKET_NAME
RESTIC_PASSWORD=$RESTIC_PASSWORD
EOF

    echo "✓ Container environment configured"
}

# Wait for container to be ready
wait_for_container() {
    local container=$1
    local max_attempts=${2:-30}
    local attempt=1

    echo "Waiting for container $container to be ready..."

    while [ $attempt -le $max_attempts ]; do
        if docker exec "$container" true 2>/dev/null; then
            echo "✓ Container is responsive"
            return 0
        fi
        echo "  Attempt $attempt/$max_attempts..."
        sleep 2
        attempt=$((attempt + 1))
    done

    echo "error: Container did not become ready"
    return 1
}

# Wait for backup service to be ready
wait_for_backup_service() {
    local container=$1
    local max_attempts=${2:-30}
    local attempt=1

    echo "Waiting for backup service to start..."

    while [ $attempt -le $max_attempts ]; do
        # Check if backup service is up via s6
        if docker exec "$container" s6-svstat /run/service/backup 2>/dev/null | grep -q "^up"; then
            echo "✓ Backup service running"
            return 0
        fi
        echo "  Attempt $attempt/$max_attempts..."
        sleep 2
        attempt=$((attempt + 1))
    done

    echo "error: Backup service did not start"
    return 1
}

# Create test data in the container
create_test_data() {
    local container=$1

    echo "Creating test data..."

    # Create test file in a backed-up path
    docker exec "$container" mkdir -p "$(dirname "$TEST_FILE_PATH")"
    docker exec "$container" bash -c "echo '$TEST_FILE_CONTENT' > '$TEST_FILE_PATH'"

    # Verify file was created
    local content
    content=$(docker exec "$container" cat "$TEST_FILE_PATH")
    if [ "$content" != "$TEST_FILE_CONTENT" ]; then
        echo "error: Failed to create test data"
        exit 1
    fi

    echo "✓ Test data created: $TEST_FILE_PATH"
}

# Trigger a backup
trigger_backup() {
    local container=$1

    echo "Triggering backup..."

    # Run backup manually
    if ! docker exec "$container" /usr/local/bin/restic-backup; then
        echo "error: Backup failed"
        exit 1
    fi

    # Verify snapshot was created
    local snapshot_count
    snapshot_count=$(docker exec "$container" bash -c 'restic snapshots --json 2>/dev/null | jq length')

    if [ "$snapshot_count" -lt 1 ]; then
        echo "error: No snapshots found after backup"
        exit 1
    fi

    echo "✓ Backup completed ($snapshot_count snapshot(s))"
}

# Restart the container (simulating redeploy)
restart_container() {
    local container=$1

    echo "Restarting container (simulating redeploy)..."

    # Stop and remove container
    docker compose -f "$PROJECT_ROOT/compose.yaml" down

    # Start fresh container
    docker compose -f "$PROJECT_ROOT/compose.yaml" up -d

    echo "✓ Container restarted"
}

# Verify test data was restored
verify_data_restored() {
    local container=$1

    echo "Verifying test data was restored..."

    # Check if test file exists and has correct content
    local content
    if ! content=$(docker exec "$container" cat "$TEST_FILE_PATH" 2>/dev/null); then
        echo "error: Test file not found after restore: $TEST_FILE_PATH"
        echo "Listing /data/.openclaw contents:"
        docker exec "$container" ls -la /data/.openclaw/ 2>/dev/null || echo "  (directory not found)"
        exit 1
    fi

    if [ "$content" != "$TEST_FILE_CONTENT" ]; then
        echo "error: Test file content mismatch"
        echo "  Expected: $TEST_FILE_CONTENT"
        echo "  Got: $content"
        exit 1
    fi

    echo "✓ Test data restored successfully!"
}

# Main test flow
main() {
    echo "========================================"
    echo "Persistence Test: DigitalOcean Spaces"
    echo "========================================"
    echo "Container: $CONTAINER"
    echo "Region: $SPACES_REGION"
    echo ""

    # Set up cleanup trap
    trap cleanup EXIT

    # Check prerequisites
    check_prerequisites

    # Create temporary Spaces bucket
    create_spaces_bucket

    # Configure container environment
    configure_container_env

    # Stop any existing container
    docker compose -f "$PROJECT_ROOT/compose.yaml" down 2>/dev/null || true

    # Start container
    echo "Starting container with persistence enabled..."
    docker compose -f "$PROJECT_ROOT/compose.yaml" up -d

    # Wait for container to be ready
    wait_for_container "$CONTAINER"

    # Wait for backup service
    wait_for_backup_service "$CONTAINER"

    # Create test data
    create_test_data "$CONTAINER"

    # Trigger backup
    trigger_backup "$CONTAINER"

    # Restart container (simulating redeploy)
    restart_container "$CONTAINER"

    # Wait for new container to be ready
    wait_for_container "$CONTAINER"

    # Wait for restore to complete (happens during init)
    echo "Waiting for restore to complete..."
    sleep 10

    # Verify data was restored
    verify_data_restored "$CONTAINER"

    echo ""
    echo "========================================"
    echo "Persistence test PASSED"
    echo "========================================"
}

main "$@"
