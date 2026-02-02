#!/bin/bash
# Test: App Platform deployment
# Verifies the app can be deployed to DigitalOcean App Platform using doctl
# Uses Tailscale sidecar to SSH into the deployed app and verify sshd works

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

# Generate unique app name (this will be the Tailscale hostname)
APP_NAME="openclaw-ci-$(date +%s)-$$"
echo "App name: $APP_NAME"

# Use CI registry if available
echo "Using CI registry: $CI_REGISTRY_NAME"
IMAGE_TAG="$CI_IMAGE_TAG"

# Parse image tag to get registry, repository, and tag
# Format: registry.digitalocean.com/REGISTRY/REPO:TAG
IMAGE_REGISTRY=$(echo "$IMAGE_TAG" | cut -d'/' -f2)
IMAGE_REPO=$(echo "$IMAGE_TAG" | cut -d'/' -f3 | cut -d':' -f1)
IMAGE_TAG_ONLY=$(echo "$IMAGE_TAG" | cut -d':' -f2)

echo "Registry: $IMAGE_REGISTRY, Repo: $IMAGE_REPO, Tag: $IMAGE_TAG_ONLY"

# Convert YAML spec to JSON and modify it to use DOCR image
# Get CI SSH public key for authorized_keys
CI_SSH_PUBKEY="${CI_SSH_PUBKEY:-}"
if [ -z "$CI_SSH_PUBKEY" ] && [ -f "$HOME/.ssh/id_ed25519_test.pub" ]; then
    CI_SSH_PUBKEY=$(cat "$HOME/.ssh/id_ed25519_test.pub")
fi
if [ -z "$CI_SSH_PUBKEY" ]; then
    echo "error: CI_SSH_PUBKEY not set and no test key found"
    exit 1
fi
echo "CI SSH public key: ${CI_SSH_PUBKEY:0:50}..."

echo ""
echo "Preparing app spec..."
APP_SPEC=$(yq -o=json "$SPEC_FILE" | jq \
    --arg name "$APP_NAME" \
    --arg registry "$IMAGE_REGISTRY" \
    --arg repo "$IMAGE_REPO" \
    --arg tag "$IMAGE_TAG_ONLY" \
    --arg ts_authkey "$TS_AUTHKEY" \
    --arg gateway_token "${OPENCLAW_GATEWAY_TOKEN:-test-token-$$}" \
    --arg ssh_pubkey "$CI_SSH_PUBKEY" \
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
    .workers[0].envs = ([
        .workers[0].envs[] |
        if .key == "TS_AUTHKEY" then .value = $ts_authkey
        elif .key == "OPENCLAW_GATEWAY_TOKEN" then .value = $gateway_token
        elif .key == "STABLE_HOSTNAME" then .value = $name
        else .
        end
    ] + [{"key": "SSH_AUTHORIZED_USERS", "scope": "RUN_TIME", "value": $ssh_pubkey}])
    ')

echo ""
echo "=== Final app spec envs ==="
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

# Get app info
APP_JSON=$(doctl apps get "$APP_ID" -o json 2>/dev/null)
echo ""
echo "App details:"
echo "$APP_JSON" | jq -r '.[0] | "ID: \(.id)\nIngress: \(.default_ingress // "none")\nPhase: \(.active_deployment.phase // "unknown")"' || true

# Wait for app to join tailnet and be reachable
echo ""
echo "Waiting for app to join tailnet (hostname: $APP_NAME)..."
TS_RETRIES=30
for i in $(seq 1 $TS_RETRIES); do
    # Check if app is reachable via Tailscale sidecar
    if docker exec tailscale-test tailscale ping --c 1 "$APP_NAME" >/dev/null 2>&1; then
        echo "✓ App is reachable on tailnet"
        break
    fi
    if [ $i -eq $TS_RETRIES ]; then
        echo "error: App not reachable on tailnet after $TS_RETRIES attempts"
        docker exec tailscale-test tailscale status || true
        exit 1
    fi
    echo "  Attempt $i/$TS_RETRIES: waiting for $APP_NAME on tailnet..."
    sleep 10
done

# Helper function to run command via Tailscale SSH
run_ts_ssh() {
    local user="$1"
    local cmd="$2"
    docker exec tailscale-test ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o GlobalKnownHostsFile=/dev/null \
        -o UpdateHostKeys=no \
        -o BatchMode=yes \
        -i /tmp/id_ed25519_test "$user@$APP_NAME" "$cmd" 2>&1
}

# Wait a bit more for services to stabilize
echo "Waiting 30s for services to stabilize..."
sleep 30

# Check if sshd is running
echo ""
echo "Checking if sshd is running via Tailscale SSH..."
SSHD_RETRIES=6
for i in $(seq 1 $SSHD_RETRIES); do
    SSHD_CHECK=$(run_ts_ssh ubuntu "pgrep -x sshd >/dev/null && echo SSHD_RUNNING || echo SSHD_NOT_RUNNING" 2>&1) || true
    echo "  SSH output: [$SSHD_CHECK]"
    if echo "$SSHD_CHECK" | grep -q "SSHD_RUNNING"; then
        echo "✓ sshd is running"
        break
    fi
    if [ $i -eq $SSHD_RETRIES ]; then
        echo "error: sshd not running after $SSHD_RETRIES attempts"
        echo "=== Debug: processes ==="
        run_ts_ssh ubuntu "ps aux" || echo "ps failed"
        echo "=== Debug: env vars ==="
        run_ts_ssh ubuntu "env | grep -E '^SSH_|^PUBLIC_'" || echo "env failed"
        exit 1
    fi
    echo "  Attempt $i/$SSHD_RETRIES: sshd not running yet, waiting 10s..."
    sleep 10
done

# Test local SSH from inside the container
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes"

echo ""
echo "Testing local SSH (via Tailscale -> ubuntu -> local SSH)..."

for target_user in ubuntu root; do
    echo "Testing: Tailscale SSH -> ubuntu -> local SSH $target_user@localhost -> motd..."
    SSH_OUTPUT=$(run_ts_ssh ubuntu "ssh $SSH_OPTS $target_user@localhost 'whoami && motd'" 2>&1) || SSH_OUTPUT="SSH_FAILED"

    echo "=== Output from $target_user ==="
    echo "$SSH_OUTPUT"
    echo "=== end ==="

    # First line should be the username
    if echo "$SSH_OUTPUT" | head -1 | grep -q "$target_user"; then
        echo "✓ Local SSH to $target_user@localhost works"
    else
        echo "error: Local SSH to $target_user@localhost failed"
        exit 1
    fi
done

# Test SSH to openclaw should fail
echo ""
echo "Testing: SSH to openclaw@localhost should be denied..."
SSH_OUTPUT=$(run_ts_ssh ubuntu "ssh $SSH_OPTS openclaw@localhost whoami 2>&1 || echo SSH_DENIED") || SSH_OUTPUT="SSH_DENIED"

if echo "$SSH_OUTPUT" | grep -qE "SSH_DENIED|Permission denied|not allowed"; then
    echo "✓ SSH to openclaw@localhost correctly denied"
else
    echo "error: SSH to openclaw@localhost should have been denied"
    echo "Got: $SSH_OUTPUT"
    exit 1
fi

echo ""
echo "App Platform deployment test passed (app will be cleaned up)"
