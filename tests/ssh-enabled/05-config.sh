#!/bin/bash
# Test: SSH configuration verification
# Verifies localaccess group, user authorized_keys, keypairs, and config files

set -e

CONTAINER=${1:?Usage: $0 <container-name>}
source "$(dirname "$0")/../lib.sh"

echo "Testing SSH configuration (container: $CONTAINER)..."

# Container should be running
docker exec "$CONTAINER" true || { echo "error: container not responsive"; exit 1; }

# Check localaccess group exists and has correct members
docker exec "$CONTAINER" getent group localaccess || { echo "error: localaccess group not found"; exit 1; }
MEMBERS=$(docker exec "$CONTAINER" getent group localaccess | cut -d: -f4)
echo "✓ localaccess group exists with members: $MEMBERS"

# Check ubuntu authorized_keys contains local access keys
docker exec "$CONTAINER" test -f /home/ubuntu/.ssh/authorized_keys || { echo "error: ubuntu authorized_keys not found"; exit 1; }
docker exec "$CONTAINER" grep -q "BEGIN LOCAL ACCESS KEYS" /home/ubuntu/.ssh/authorized_keys || { echo "error: local access keys not found in ubuntu authorized_keys"; exit 1; }
echo "✓ ubuntu authorized_keys contains local access keys"

# Check root authorized_keys contains local access keys
docker exec "$CONTAINER" test -f /root/.ssh/authorized_keys || { echo "error: root authorized_keys not found"; exit 1; }
docker exec "$CONTAINER" grep -q "BEGIN LOCAL ACCESS KEYS" /root/.ssh/authorized_keys || { echo "error: local access keys not found in root authorized_keys"; exit 1; }
echo "✓ root authorized_keys contains local access keys"

# Check SSH keypairs exist for ubuntu
docker exec "$CONTAINER" test -f /home/ubuntu/.ssh/id_ed25519 || { echo "error: ubuntu SSH key not found"; exit 1; }
docker exec "$CONTAINER" test -f /home/ubuntu/.ssh/id_ed25519.pub || { echo "error: ubuntu SSH pubkey not found"; exit 1; }
echo "✓ ubuntu SSH keypair exists"

# Check SSH keypairs exist for root
docker exec "$CONTAINER" test -f /root/.ssh/id_ed25519 || { echo "error: root SSH key not found"; exit 1; }
docker exec "$CONTAINER" test -f /root/.ssh/id_ed25519.pub || { echo "error: root SSH pubkey not found"; exit 1; }
echo "✓ root SSH keypair exists"

# Check sshd config files
docker exec "$CONTAINER" test -f /etc/ssh/sshd_config.d/00-localssh.conf || { echo "error: sshd config not found"; exit 1; }
docker exec "$CONTAINER" test -f /etc/ssh/sshd_config.d/local-access.conf || { echo "error: local-access config not found"; exit 1; }
echo "✓ SSH config files exist"

echo "SSH configuration tests passed"
