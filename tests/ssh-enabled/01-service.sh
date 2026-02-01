#!/bin/bash
# Test: SSH enabled configuration
# Comprehensive SSH tests including local access, external access, and security

set -e

CONTAINER=${1:?Usage: $0 <container-name>}
source "$(dirname "$0")/../lib.sh"

echo "Testing SSH service (container: $CONTAINER)..."

# Container should be running
docker exec "$CONTAINER" true || { echo "error: container not responsive"; exit 1; }

# SSH should be running
wait_for_process "$CONTAINER" "sshd" || { echo "error: sshd not running but SSH_ENABLE=true"; exit 1; }

# SSH port should be listening
docker exec "$CONTAINER" bash -c 'echo > /dev/tcp/127.0.0.1/22' 2>/dev/null || { echo "error: SSH not listening on port 22"; exit 1; }
echo "✓ SSH listening on port 22"

# s6 service should be up
assert_service_up "$CONTAINER" "sshd" || exit 1

# ============================================================================
# SSH CONFIGURATION VERIFICATION
# ============================================================================
echo ""
echo "=== SSH Configuration Verification ==="

# Check localaccess group exists and has correct members
docker exec "$CONTAINER" getent group localaccess || { echo "error: localaccess group not found"; exit 1; }
MEMBERS=$(docker exec "$CONTAINER" getent group localaccess | cut -d: -f4)
echo "✓ localaccess group exists with members: $MEMBERS"

# Check system-wide authorized_keys exists and has keys
docker exec "$CONTAINER" test -f /etc/ssh/authorized_keys || { echo "error: /etc/ssh/authorized_keys not found"; exit 1; }
KEY_COUNT=$(docker exec "$CONTAINER" wc -l /etc/ssh/authorized_keys | awk '{print $1}')
echo "✓ /etc/ssh/authorized_keys exists with $KEY_COUNT keys"

# Check SSH keypairs exist
docker exec "$CONTAINER" test -f /home/ubuntu/.ssh/id_ed25519 || { echo "error: ubuntu SSH key not found"; exit 1; }
docker exec "$CONTAINER" test -f /home/ubuntu/.ssh/id_ed25519.pub || { echo "error: ubuntu SSH pubkey not found"; exit 1; }
echo "✓ ubuntu SSH keypair exists"

docker exec "$CONTAINER" test -f /root/.ssh/id_ed25519 || { echo "error: root SSH key not found"; exit 1; }
docker exec "$CONTAINER" test -f /root/.ssh/id_ed25519.pub || { echo "error: root SSH pubkey not found"; exit 1; }
echo "✓ root SSH keypair exists"

# Check sshd config files
docker exec "$CONTAINER" test -f /etc/ssh/sshd_config.d/00-localssh.conf || { echo "error: sshd config not found"; exit 1; }
docker exec "$CONTAINER" test -f /etc/ssh/sshd_config.d/local-access.conf || { echo "error: local-access config not found"; exit 1; }
echo "✓ SSH config files exist"

# ============================================================================
# LOCAL SSH TESTS (inside container)
# ============================================================================
echo ""
echo "=== Local SSH Tests (inside container) ==="

# Test all user combinations
assert_ssh_works "$CONTAINER" ubuntu ubuntu || exit 1
assert_ssh_works "$CONTAINER" ubuntu root || exit 1
assert_ssh_works "$CONTAINER" ubuntu openclaw || exit 1
assert_ssh_works "$CONTAINER" root ubuntu || exit 1
assert_ssh_works "$CONTAINER" root root || exit 1
assert_ssh_works "$CONTAINER" root openclaw || exit 1

# Test command execution
echo "Testing command execution via SSH..."
RESULT=$(docker exec "$CONTAINER" su - ubuntu -c \
    "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes root@localhost 'echo test-output-123'" 2>/dev/null)
[ "$RESULT" = "test-output-123" ] || { echo "error: Expected 'test-output-123', got '$RESULT'"; exit 1; }
echo "✓ Command execution works"

# Test environment variable passing (MOTD_SKIP)
echo "Testing MOTD_SKIP environment variable..."
docker exec "$CONTAINER" su - ubuntu -c \
    "MOTD_SKIP=1 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o SendEnv=MOTD_SKIP root@localhost 'echo \$MOTD_SKIP'" \
    2>/dev/null | grep -q "1" && echo "✓ MOTD_SKIP passed correctly" || echo "warning: MOTD_SKIP not passed (non-critical)"

# ============================================================================
# EXTERNAL SSH TESTS (via exposed port 2222)
# ============================================================================
echo ""
echo "=== External SSH Tests (via port 2222) ==="

CI_KEY="$HOME/.ssh/id_ed25519_test"
if [ -f "$CI_KEY" ]; then
    wait_for_ssh_port localhost 2222 || { echo "error: SSH port 2222 not reachable"; exit 1; }

    # Test external SSH to ubuntu
    assert_external_ssh_works localhost 2222 ubuntu "$CI_KEY" || exit 1

    # Test command execution via external SSH
    echo "Testing command execution via external SSH..."
    RESULT=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes \
        -o ConnectTimeout=10 -i "$CI_KEY" -p 2222 ubuntu@localhost 'hostname' 2>/dev/null)
    echo "✓ External command output: $RESULT"

    # Test chained SSH: external -> ubuntu -> root
    echo "Testing chained SSH (external -> ubuntu -> root)..."
    RESULT=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes \
        -o ConnectTimeout=10 -i "$CI_KEY" -p 2222 ubuntu@localhost \
        'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes root@localhost whoami' 2>/dev/null)
    [ "$RESULT" = "root" ] || { echo "error: Chained SSH failed, got: $RESULT"; exit 1; }
    echo "✓ Chained SSH works"

    # Test file transfer capability
    echo "Testing SCP file transfer..."
    echo "test-content-$$" > /tmp/test-upload-$$.txt
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes \
        -i "$CI_KEY" -P 2222 /tmp/test-upload-$$.txt ubuntu@localhost:/tmp/ 2>/dev/null || { echo "error: SCP upload failed"; exit 1; }
    RESULT=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes \
        -o ConnectTimeout=10 -i "$CI_KEY" -p 2222 ubuntu@localhost "cat /tmp/test-upload-$$.txt" 2>/dev/null)
    [ "$RESULT" = "test-content-$$" ] || { echo "error: SCP content mismatch"; exit 1; }
    echo "✓ SCP file transfer works"
    rm -f /tmp/test-upload-$$.txt
else
    echo "warning: CI test key not found, skipping external SSH tests"
fi

# ============================================================================
# NEGATIVE TEST CASES
# ============================================================================
echo ""
echo "=== Negative Test Cases ==="

# Test password authentication is disabled
echo "Testing password authentication is disabled..."
docker exec "$CONTAINER" bash -c '
    useradd -m pwdtestuser 2>/dev/null || true
    echo "pwdtestuser:testpass123" | chpasswd
'
if docker exec "$CONTAINER" su - ubuntu -c \
    "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o PreferredAuthentications=password pwdtestuser@localhost whoami" 2>/dev/null; then
    echo "error: Password authentication should be disabled"
    docker exec "$CONTAINER" userdel -r pwdtestuser 2>/dev/null || true
    exit 1
fi
echo "✓ Password authentication disabled"
docker exec "$CONTAINER" userdel -r pwdtestuser 2>/dev/null || true

# Test non-localaccess user cannot SSH to root
echo "Testing non-localaccess user cannot SSH to root..."
docker exec "$CONTAINER" bash -c '
    useradd -m testuser 2>/dev/null || true
    mkdir -p /home/testuser/.ssh
    ssh-keygen -t ed25519 -N "" -f /home/testuser/.ssh/id_ed25519 -C "testuser@test" >/dev/null 2>&1
    chown -R testuser:testuser /home/testuser/.ssh
'
if docker exec "$CONTAINER" su - testuser -c \
    "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=5 root@localhost whoami" 2>/dev/null; then
    echo "error: Non-localaccess user should not SSH to root"
    docker exec "$CONTAINER" userdel -r testuser 2>/dev/null || true
    exit 1
fi
echo "✓ Non-localaccess user correctly denied"
docker exec "$CONTAINER" userdel -r testuser 2>/dev/null || true

# Test external SSH with unauthorized key is denied
echo "Testing unauthorized SSH key is denied..."
if [ -f "$CI_KEY" ]; then
    WRONG_KEY="/tmp/wrong_key_$$"
    ssh-keygen -t ed25519 -N "" -f "$WRONG_KEY" -C "unauthorized@key" >/dev/null 2>&1
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes \
        -o ConnectTimeout=5 -i "$WRONG_KEY" -p 2222 ubuntu@localhost whoami 2>/dev/null; then
        echo "error: Unauthorized key should be denied"
        rm -f "$WRONG_KEY" "${WRONG_KEY}.pub"
        exit 1
    fi
    echo "✓ Unauthorized key correctly denied"
    rm -f "$WRONG_KEY" "${WRONG_KEY}.pub"
fi

# Test external root login is denied (only localhost allowed)
echo "Testing external root login is denied..."
if [ -f "$CI_KEY" ]; then
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes \
        -o ConnectTimeout=5 -i "$CI_KEY" -p 2222 root@localhost whoami 2>/dev/null; then
        echo "error: External root login should be denied"
        exit 1
    fi
    echo "✓ External root login correctly denied"
fi

echo ""
echo "ssh-enabled tests passed"
