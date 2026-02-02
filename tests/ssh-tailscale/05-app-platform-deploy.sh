#!/bin/bash
# Test: App Platform deployment
# Verifies the app can be deployed to DigitalOcean App Platform using doctl
# Uses CI registry (CI_REGISTRY_NAME, CI_IMAGE_TAG) when available, otherwise creates own

set -e

CONTAINER=${1:?Usage: $0 <container-name>}
source "$(dirname "$0")/../lib.sh"

SPEC_FILE="$(dirname "$0")/app-ssh-local.spec.yaml"
APP_ID=""
REGISTRY_NAME=""
OWN_REGISTRY=false

# Dump app state for debugging
dump_app_state() {
    if [ -z "$APP_ID" ]; then
        echo "No APP_ID set, skipping dump"
        return
    fi
    echo ""
    echo "=== Dumping app state for debugging ==="
    echo "App ID: $APP_ID"

    # Get component name
    local component=$(doctl apps get "$APP_ID" -o json 2>/dev/null | jq -r '.spec.workers[0].name // empty')
    [ -z "$component" ] && component="$APP_NAME"

    echo ""
    echo "=== App JSON ==="
    doctl apps get "$APP_ID" -o json 2>/dev/null | jq '.' || true

    echo ""
    echo "=== Build logs ==="
    doctl apps logs "$APP_ID" --type=build 2>/dev/null | tail -100 || true

    echo ""
    echo "=== Run logs ==="
    doctl apps logs "$APP_ID" --type=run 2>/dev/null | tail -100 || true

    echo ""
    echo "=== Process list (ps aux) ==="
    echo "ps aux" | timeout 30 doctl apps console "$APP_ID" "$component" 2>/dev/null || echo "Failed to get process list"

    echo ""
    echo "=== End of dump ==="
}

# Trap to dump state on failure
trap 'dump_app_state' ERR

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

echo "Creating app on App Platform..."
CREATE_OUTPUT=$(doctl apps create --spec - -o json --wait << EOF
$APP_SPEC
EOF
) || {
    echo "error: Failed to create app"
    echo "$CREATE_OUTPUT"
    exit 1
}

APP_ID=$(echo "$CREATE_OUTPUT" | jq -r '.id // empty')
if [ -z "$APP_ID" ]; then
    echo "error: Failed to get app ID from creation output"
    echo "$CREATE_OUTPUT"
    exit 1
fi
echo "✓ Created app: $APP_ID"

# Output app ID for cleanup step
if [ -n "$GITHUB_OUTPUT" ]; then
    echo "app_id=$APP_ID" >> "$GITHUB_OUTPUT"
fi

# Wait for app to be fully deployed (ACTIVE status)
echo "Waiting for app deployment (this may take several minutes)..."
DEPLOY_TIMEOUT=1200  # 20 minutes
DEPLOY_START=$(date +%s)

while true; do
    ELAPSED=$(($(date +%s) - DEPLOY_START))
    APP_JSON=$(doctl apps get "$APP_ID" -o json 2>/dev/null)
    echo "DEBUG JSON: $APP_JSON" | head -c 500
    APP_STATUS=$(echo "$APP_JSON" | jq -r '.active_deployment.phase // "PENDING"')
    echo "  [$ELAPSED s] Status: $APP_STATUS"

    case "$APP_STATUS" in
        ACTIVE)
            echo "✓ App deployed successfully"
            break
            ;;
        PENDING|PENDING_BUILD|BUILDING|PENDING_DEPLOY|DEPLOYING)
            # Still in progress, continue waiting
            ;;
        ERROR|CANCELED)
            echo "error: App deployment failed with status: $APP_STATUS"
            doctl apps logs "$APP_ID" --type=build 2>/dev/null | tail -50 || true
            exit 1
            ;;
    esac

    if [ $ELAPSED -ge $DEPLOY_TIMEOUT ]; then
        echo "error: Deployment timed out after ${DEPLOY_TIMEOUT}s"
        doctl apps logs "$APP_ID" --type=build 2>/dev/null | tail -50 || true
        exit 1
    fi
    sleep 10
done

# Get app info
echo ""
echo "App details:"
doctl apps get "$APP_ID" --format ID,DefaultIngress,ActiveDeployment.Phase 2>/dev/null || true

# Get component name for console access
COMPONENT_NAME=$(doctl apps get "$APP_ID" --format Spec.Workers[0].Name --no-header 2>/dev/null || echo "$APP_NAME")
echo "Component: $COMPONENT_NAME"

# Test app via console - verify SSH is working
echo ""
echo "Testing app via console..."

# First, figure out who we are
echo "Checking current user..."
CURRENT_USER=$(echo "whoami" | timeout 30 doctl apps console "$APP_ID" "$COMPONENT_NAME" 2>/dev/null | tr -d '\r' | tail -1) || {
    echo "error: Failed to get current user via console"
    exit 1
}
echo "✓ Console user: $CURRENT_USER"

# Check if sshd is running
echo "Checking if sshd is running..."
SSHD_CHECK=$(echo "pgrep -x sshd >/dev/null && echo SSHD_RUNNING || echo SSHD_NOT_RUNNING" | timeout 30 doctl apps console "$APP_ID" "$COMPONENT_NAME" 2>/dev/null | tr -d '\r' | tail -1) || true
if [ "$SSHD_CHECK" != "SSHD_RUNNING" ]; then
    echo "error: sshd is not running"
    exit 1
fi
echo "✓ sshd is running"

# Test SSH to different users
for target_user in ubuntu openclaw root; do
    echo "Testing SSH from $CURRENT_USER to $target_user@localhost..."
    SSH_OUTPUT=$(echo "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes $target_user@localhost 'whoami && motd' 2>/dev/null || echo SSH_FAILED" | timeout 30 doctl apps console "$APP_ID" "$COMPONENT_NAME" 2>/dev/null | tr -d '\r') || SSH_OUTPUT="SSH_FAILED"

    # First line should be the username
    SSH_USER=$(echo "$SSH_OUTPUT" | head -1)
    if [ "$SSH_USER" = "$target_user" ]; then
        echo "✓ SSH to $target_user@localhost works"
        echo "$SSH_OUTPUT" | tail -n +2 | head -20
    else
        echo "error: SSH to $target_user@localhost failed (got: $SSH_USER)"
        echo "$SSH_OUTPUT"
        exit 1
    fi
done

# Dump app state before cleanup
dump_app_state

echo ""
echo "App Platform deployment test passed (app will be cleaned up)"
