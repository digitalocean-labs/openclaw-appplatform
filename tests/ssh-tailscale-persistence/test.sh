#!/bin/bash
# Test: SSH + Tailscale + Persistence enabled
# Full integration test with all features

set -e

CONTAINER=${1:?Usage: $0 <container-name>}
source "$(dirname "$0")/../lib.sh"

echo "Testing ssh-tailscale-persistence configuration (container: $CONTAINER)..."

# Container should be running
docker exec "$CONTAINER" true || { echo "error: container not responsive"; exit 1; }

# ============================================================================
# SSH TESTS
# ============================================================================
echo ""
echo "=== SSH Tests ==="

wait_for_process "$CONTAINER" "sshd" || { echo "error: sshd not running"; exit 1; }

# Local SSH - all combinations
assert_ssh_works "$CONTAINER" ubuntu ubuntu || exit 1
assert_ssh_works "$CONTAINER" ubuntu root || exit 1
assert_ssh_works "$CONTAINER" root ubuntu || exit 1
assert_ssh_works "$CONTAINER" root root || exit 1

# External SSH
CI_KEY="$HOME/.ssh/id_ed25519_test"
if [ -f "$CI_KEY" ]; then
    wait_for_ssh_port localhost 2222 || { echo "error: SSH port 2222 not reachable"; exit 1; }
    assert_external_ssh_works localhost 2222 ubuntu "$CI_KEY" || exit 1

    # Chained SSH
    echo "Testing chained SSH..."
    RESULT=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes \
        -o ConnectTimeout=10 -i "$CI_KEY" -p 2222 ubuntu@localhost \
        'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes root@localhost whoami' 2>/dev/null)
    [ "$RESULT" = "root" ] || { echo "error: Chained SSH failed"; exit 1; }
    echo "✓ Chained SSH works"
fi

# ============================================================================
# TAILSCALE TESTS
# ============================================================================
echo ""
echo "=== Tailscale Tests ==="

if [ "${SKIP_TAILSCALE:-false}" != "true" ]; then
    wait_for_process "$CONTAINER" "tailscaled" || { echo "error: tailscaled not running"; exit 1; }

    # Wait for Tailscale to connect and get IP
    echo "Waiting for Tailscale to connect..."
    TS_IP=""
    for i in {1..60}; do
        TS_IP=$(docker exec "$CONTAINER" tailscale ip -4 2>/dev/null || echo "")
        if [ -n "$TS_IP" ]; then
            echo "✓ Tailscale IP: $TS_IP"
            break
        fi
        [ $i -eq 60 ] && { echo "error: Failed to get Tailscale IP"; exit 1; }
        sleep 2
    done

    # Test SSH via Tailscale from sidecar
    if docker ps --filter name=tailscale-test --format '{{.Names}}' | grep -q tailscale-test; then
        echo "Testing SSH via Tailscale network..."
        # Wait for connectivity
        for i in {1..15}; do
            if docker exec tailscale-test ping -c 1 -W 2 "$TS_IP" >/dev/null 2>&1; then
                break
            fi
            sleep 2
        done

        SSH_RESULT=$(docker exec tailscale-test ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o BatchMode=yes -o ConnectTimeout=30 -i /tmp/id_ed25519_test \
            "ubuntu@$TS_IP" 'whoami' 2>&1) || true
        if echo "$SSH_RESULT" | grep -q "ubuntu"; then
            echo "✓ SSH via Tailscale works"
        else
            echo "warning: SSH via Tailscale failed (non-critical)"
            echo "  Debug: $SSH_RESULT"
        fi
    fi
else
    echo "Skipping Tailscale tests (no credentials)"
fi

# ============================================================================
# PERSISTENCE TESTS
# ============================================================================
echo ""
echo "=== Persistence Tests ==="

if [ -z "$DO_SPACES_ACCESS_KEY_ID" ] || [ -z "$DO_SPACES_SECRET_ACCESS_KEY" ]; then
    echo "Skipping persistence tests (no DO_SPACES credentials)"
else
    # Restic should be configured
    docker exec "$CONTAINER" test -f /run/s6/container_environment/RESTIC_REPOSITORY || {
        echo "error: RESTIC_REPOSITORY not set"; exit 1;
    }
    echo "✓ Restic repository configured"

    # Backup service should be running
    assert_service_up "$CONTAINER" backup || echo "warning: backup service not up yet"
    assert_service_up "$CONTAINER" prune || echo "warning: prune service not up yet"
fi

# ============================================================================
# NEGATIVE TEST CASES
# ============================================================================
echo ""
echo "=== Negative Test Cases ==="

# Password auth disabled
echo "Testing password authentication is disabled..."
docker exec "$CONTAINER" bash -c 'useradd -m pwdtest 2>/dev/null || true; echo "pwdtest:pass123" | chpasswd'
if docker exec "$CONTAINER" su - ubuntu -c \
    "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o PreferredAuthentications=password pwdtest@localhost whoami" 2>/dev/null; then
    docker exec "$CONTAINER" userdel -r pwdtest 2>/dev/null || true
    echo "error: Password auth should be disabled"; exit 1
fi
echo "✓ Password authentication disabled"
docker exec "$CONTAINER" userdel -r pwdtest 2>/dev/null || true

# Non-localaccess user denied
echo "Testing non-localaccess user denied..."
docker exec "$CONTAINER" bash -c '
    useradd -m testuser 2>/dev/null || true
    mkdir -p /home/testuser/.ssh
    ssh-keygen -t ed25519 -N "" -f /home/testuser/.ssh/id_ed25519 -C "testuser" >/dev/null 2>&1
    chown -R testuser:testuser /home/testuser/.ssh
'
if docker exec "$CONTAINER" su - testuser -c \
    "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=5 root@localhost whoami" 2>/dev/null; then
    docker exec "$CONTAINER" userdel -r testuser 2>/dev/null || true
    echo "error: Non-localaccess user should be denied"; exit 1
fi
echo "✓ Non-localaccess user denied"
docker exec "$CONTAINER" userdel -r testuser 2>/dev/null || true

# Unauthorized key denied
if [ -f "$CI_KEY" ]; then
    echo "Testing unauthorized key denied..."
    WRONG_KEY="/tmp/wrong_key_$$"
    ssh-keygen -t ed25519 -N "" -f "$WRONG_KEY" -C "wrong" >/dev/null 2>&1
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes \
        -o ConnectTimeout=5 -i "$WRONG_KEY" -p 2222 ubuntu@localhost whoami 2>/dev/null; then
        rm -f "$WRONG_KEY" "${WRONG_KEY}.pub"
        echo "error: Unauthorized key should be denied"; exit 1
    fi
    echo "✓ Unauthorized key denied"
    rm -f "$WRONG_KEY" "${WRONG_KEY}.pub"

    # External root login denied
    echo "Testing external root login denied..."
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes \
        -o ConnectTimeout=5 -i "$CI_KEY" -p 2222 root@localhost whoami 2>/dev/null; then
        echo "error: External root login should be denied"; exit 1
    fi
    echo "✓ External root login denied"
fi

echo ""
echo "ssh-tailscale-persistence tests passed"
