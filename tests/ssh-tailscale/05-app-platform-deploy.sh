#!/bin/bash
# Test: App Platform deployment
# Verifies the app can be deployed to DigitalOcean App Platform using doctl
# Uses CI registry (CI_REGISTRY_NAME, CI_IMAGE_TAG) when available, otherwise creates own

set -e

CONTAINER=${1:?Usage: $0 <container-name>}
source "$(dirname "$0")/../lib.sh"

SPEC_FILE="$(dirname "$0")/app-ssh-local.spec.yaml"
APP_ID=""

echo "Testing App Platform deployment..."

# Use DIGITALOCEAN_TOKEN env var if set (passed from workflow)
if [ -n "$DIGITALOCEAN_TOKEN" ]; then
    export DIGITALOCEAN_ACCESS_TOKEN="$DIGITALOCEAN_TOKEN"
fi

if [ -z "$TS_AUTHKEY" ]; then
    echo "error: TS_AUTHKEY not set (required for app deployment)"
    exit 1
fi

# Verify doctl is available
if ! command -v doctl &>/dev/null; then
    echo "error: doctl not installed"
    exit 1
fi

# Verify spec file exists
if [ ! -f "$SPEC_FILE" ]; then
    echo "error: Spec file not found: $SPEC_FILE"
    exit 1
fi

# Generate unique app name
APP_NAME="openclaw-ci-$(date +%s)-$$"
echo "App name: $APP_NAME"

# Use CI registry if available, otherwise create our own
echo "Using CI registry: $CI_REGISTRY_NAME"
IMAGE_TAG="$CI_IMAGE_TAG"

# Parse image tag to get registry, repository, and tag
# Format: registry.digitalocean.com/REGISTRY/REPO:TAG
IMAGE_REGISTRY=$(echo "$IMAGE_TAG" | cut -d'/' -f2)
IMAGE_REPO=$(echo "$IMAGE_TAG" | cut -d'/' -f3 | cut -d':' -f1)
IMAGE_TAG_ONLY=$(echo "$IMAGE_TAG" | cut -d':' -f2)

echo "Registry: $IMAGE_REGISTRY, Repo: $IMAGE_REPO, Tag: $IMAGE_TAG_ONLY"

# Convert YAML spec to JSON and modify it to use DOCR image
echo ""
echo "Preparing app spec..."
APP_SPEC=$(yq -o=json "$SPEC_FILE" | jq \
    --arg name "$APP_NAME" \
    --arg registry "$IMAGE_REGISTRY" \
    --arg repo "$IMAGE_REPO" \
    --arg tag "$IMAGE_TAG_ONLY" \
    --arg ts_authkey "$TS_AUTHKEY" \
    --arg gateway_token "${OPENCLAW_GATEWAY_TOKEN:-test-token-$$}" \
    '
    .name = $name |
    .workers[0].name = $name |
    del(.workers[0].git) |
    del(.workers[0].dockerfile_path) |
    del(.workers[0].source_dir) |
    .workers[0].image = {
        "registry_type": "DOCR",
        "registry": $registry,
        "repository": $repo,
        "tag": $tag
    } |
    .workers[0].envs = [
        .workers[0].envs[] |
        if .key == "TS_AUTHKEY" then .value = $ts_authkey
        elif .key == "OPENCLAW_GATEWAY_TOKEN" then .value = $gateway_token
        elif .key == "STABLE_HOSTNAME" then .value = $name
        else .
        end
    ]
    ')

echo ""
echo "=== Final app spec ==="
echo "$APP_SPEC" | jq '.workers[0].envs'
echo "=== end spec ==="

echo "Creating app on App Platform (waiting for deployment)..."
CREATE_OUTPUT=$(doctl apps create --spec - --wait -o json <<EOF
$APP_SPEC
EOF
) || {
    echo "error: Failed to create app"
    echo "$CREATE_OUTPUT"
    exit 1
}

APP_ID=$(echo "$CREATE_OUTPUT" | jq -r '.[0].id // empty')
if [ -z "$APP_ID" ]; then
    echo "error: Failed to get app ID from creation output"
    echo "$CREATE_OUTPUT"
    exit 1
fi
echo "✓ App deployed: $APP_ID"

# Output app ID for cleanup step
if [ -n "$GITHUB_OUTPUT" ]; then
    echo "app_id=$APP_ID" >> "$GITHUB_OUTPUT"
fi

# Get app info and component name
APP_JSON=$(doctl apps get "$APP_ID" -o json 2>/dev/null)
echo ""
echo "App details:"
echo "$APP_JSON" | jq -r '.[0] | "ID: \(.id)\nIngress: \(.default_ingress // "none")\nPhase: \(.active_deployment.phase // "unknown")"' || true

COMPONENT_NAME=$(echo "$APP_JSON" | jq -r '.[0].spec.workers[0].name // empty')
[ -z "$COMPONENT_NAME" ] && COMPONENT_NAME="$APP_NAME"
echo "Component: $COMPONENT_NAME"

# Wait for container to be fully ready
echo ""
echo "Waiting 60s for container to stabilize..."
sleep 60

# Test app via console - verify SSH is working
echo ""
echo "Testing app via console..."

# Helper function to run console command with pseudo-TTY
run_console() {
    local cmd="$1"
    # Use script to provide a pseudo-TTY since doctl console requires it
    script -q -c "echo '$cmd' | timeout 60 doctl apps console '$APP_ID' '$COMPONENT_NAME'" /dev/null 2>&1 | tr -d '\r'
}

# Debug: dump env and service status
echo "=== Debug: env vars and services ==="
run_console "env | grep -E '^SSH_|^PUBLIC_' ; /command/s6-svstat /run/service/sshd ; ps aux | grep -E 'sshd|s6' | head -10"
echo "=== end debug ==="

# First, figure out who we are
echo "Checking current user..."
CONSOLE_OUTPUT=$(run_console "whoami")
echo "Raw console output: [$CONSOLE_OUTPUT]"
CURRENT_USER=$(echo "$CONSOLE_OUTPUT" | grep -v "^$" | tail -1)
echo "✓ Console user: $CURRENT_USER"

if [ -z "$CURRENT_USER" ]; then
    echo "warning: Could not determine console user, continuing anyway..."
fi

# Check if sshd is running with retry
echo "Checking if sshd is running..."
SSHD_RETRIES=6
for i in $(seq 1 $SSHD_RETRIES); do
    CONSOLE_OUTPUT=$(run_console "pgrep -x sshd >/dev/null && echo SSHD_RUNNING || echo SSHD_NOT_RUNNING")
    echo "  Console output: [$CONSOLE_OUTPUT]"
    SSHD_CHECK=$(echo "$CONSOLE_OUTPUT" | grep -oE "SSHD_(RUNNING|NOT_RUNNING)" | tail -1)
    if [ "$SSHD_CHECK" = "SSHD_RUNNING" ]; then
        echo "✓ sshd is running"
        break
    fi
    echo "  Attempt $i/$SSHD_RETRIES: sshd not running yet (got: $SSHD_CHECK), waiting 10s..."
    sleep 10
done

if [ "$SSHD_CHECK" != "SSHD_RUNNING" ]; then
    echo "error: sshd is not running after $SSHD_RETRIES attempts"
    echo "=== Debug: all processes ==="
    run_console "ps aux"
    echo "=== end debug ==="
    exit 1
fi

# Test SSH to users that should work (ubuntu, root) with nested SSH
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes"

for target_user in ubuntu root; do
    echo "Testing console → SSH $target_user@localhost → motd → SSH root@localhost → motd..."
    SSH_CMD="ssh $SSH_OPTS $target_user@localhost 'motd && ssh $SSH_OPTS root@localhost motd'"
    SSH_OUTPUT=$(run_console "$SSH_CMD") || SSH_OUTPUT="SSH_FAILED"

    # Dump full motd output
    echo "=== motd output from $target_user ==="
    echo "$SSH_OUTPUT"
    echo "=== end motd ==="

    # Check for motd output (should appear twice - once per SSH hop)
    MOTD_COUNT=$(echo "$SSH_OUTPUT" | grep -c "Welcome\|openclaw" || true)
    if [ "$MOTD_COUNT" -ge 2 ]; then
        echo "✓ Nested SSH from $target_user works (motd appeared $MOTD_COUNT times)"
    else
        echo "error: Nested SSH from $target_user failed (motd count: $MOTD_COUNT)"
        exit 1
    fi
done

# Test SSH to openclaw should fail (no local SSH access for service account)
echo "Testing console → SSH openclaw@localhost should be denied..."
SSH_OUTPUT=$(run_console "ssh $SSH_OPTS openclaw@localhost motd 2>&1 || echo SSH_DENIED") || SSH_OUTPUT="SSH_DENIED"

if echo "$SSH_OUTPUT" | grep -q "SSH_DENIED\|Permission denied\|not allowed"; then
    echo "✓ SSH to openclaw@localhost correctly denied"
else
    echo "error: SSH to openclaw@localhost should have been denied but got: $SSH_OUTPUT"
    exit 1
fi

echo ""
echo "App Platform deployment test passed (app will be cleaned up)"
