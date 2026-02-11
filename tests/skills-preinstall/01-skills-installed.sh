#!/bin/bash
# Test: Skills pre-installed from OPENCLAW_SKILLS env var
# Verifies that skills listed in OPENCLAW_SKILLS are installed via pnpm

set -e

CONTAINER=${1:?Usage: $0 <container-name>}
source "$(dirname "$0")/../lib.sh"

echo "Testing skills pre-installation (container: $CONTAINER)..."

# Wait for container to be fully initialized
wait_for_container "$CONTAINER"

# Verify the is-number package was installed globally for the openclaw user
if docker exec "$CONTAINER" su - openclaw -c 'source $HOME/.nvm/nvm.sh && export PNPM_HOME="$HOME/.local/share/pnpm" && export PATH="$PNPM_HOME:$PATH" && pnpm list -g is-number' 2>&1 | grep -q "is-number"; then
    echo "✓ is-number skill installed via OPENCLAW_SKILLS env var"
else
    echo "error: is-number skill not found in global pnpm packages"
    echo "--- pnpm global list ---"
    docker exec "$CONTAINER" su - openclaw -c 'source $HOME/.nvm/nvm.sh && export PNPM_HOME="$HOME/.local/share/pnpm" && export PATH="$PNPM_HOME:$PATH" && pnpm list -g' 2>&1
    exit 1
fi

echo "Skills pre-installation tests passed"
