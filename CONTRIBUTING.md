# Contributing

## Testing

This project uses a matrix-based CI system that automatically tests multiple configuration combinations.

### How Tests Work

The CI workflow (`.github/workflows/test.yml`) runs in two stages:

1. **Discovery**: Scans `example_configs/` for `.env` files
2. **Matrix Build**: Runs a parallel Docker build + verification for each config

Each test:
- Builds the Docker image
- Starts the container with the specific configuration
- Waits for services to initialize
- Verifies the container is running
- Runs config-specific test script from `tests/<config-name>/test.sh`
- Collects logs and diagnostics on failure

### Adding a New Test Configuration

1. Create a new `.env` file in `example_configs/`:

```bash
# example_configs/my-new-config.env

# Description comment explaining what this tests
TAILSCALE_ENABLE=false
ENABLE_NGROK=false
ENABLE_SPACES=false
SSH_ENABLE=false
ENABLE_UI=true
# IMPORTANT: STABLE_HOSTNAME must match the config filename (without .env)
# This is used as the container name and passed to test scripts
STABLE_HOSTNAME=my-new-config
S6_BEHAVIOUR_IF_STAGE2_FAILS=0
```

2. Create a test script in `tests/<config-name>/test.sh`:

```bash
#!/bin/bash
# tests/my-new-config/test.sh
set -e

# Container name is passed as first argument
CONTAINER=${1:?Usage: $0 <container-name>}

echo "Testing my-new-config (container: $CONTAINER)..."

# Container should be running
docker exec "$CONTAINER" true || { echo "error: container not responsive"; exit 1; }

# Check s6 services
docker exec "$CONTAINER" s6-rc -a list | grep -q moltbot || { echo "error: moltbot service not supervised"; exit 1; }
echo "✓ moltbot service supervised"

# Add your specific verifications here...

echo "my-new-config tests passed"
```

3. Make the script executable:

```bash
chmod +x tests/my-new-config/test.sh
```

4. The workflow will automatically pick it up on the next CI run.

### Configuration Options

| Variable | Values | Description |
|----------|--------|-------------|
| `TAILSCALE_ENABLE` | `true`/`false` | Enable Tailscale networking |
| `ENABLE_NGROK` | `true`/`false` | Enable ngrok tunnel |
| `ENABLE_SPACES` | `true`/`false` | Enable DO Spaces backup |
| `SSH_ENABLE` | `true`/`false` | Enable SSH server |
| `ENABLE_UI` | `true`/`false` | Enable web UI |
| `STABLE_HOSTNAME` | string | Container hostname |
| `S6_BEHAVIOUR_IF_STAGE2_FAILS` | `0`/`1`/`2` | s6 failure behavior (0=continue) |

### Test Scripts

Each configuration has a corresponding test script in `tests/<config-name>/test.sh`. Test scripts:

- Receive the container name as the first argument (`$1`)
- Run after the container starts and services initialize
- Should use `set -e` to fail fast on errors
- Should verify expected services are running and unexpected services are NOT running

Common verification patterns:

```bash
CONTAINER=${1:?Usage: $0 <container-name>}

# Check s6 service is supervised
docker exec "$CONTAINER" s6-rc -a list | grep -q <service>

# Check process is running
docker exec "$CONTAINER" pgrep -x <process>

# Check process is NOT running
if docker exec "$CONTAINER" pgrep -x <process> >/dev/null 2>&1; then
    echo "error: <process> should not be running"
    exit 1
fi

# Check port is listening
docker exec "$CONTAINER" ss -tlnp | grep -q ":<port> "
```

### Running Tests Locally

```bash
# Test a specific configuration
cp example_configs/minimal.env .env
make rebuild

# Wait for services to start
sleep 10

# Run the test script (container name = config name = "minimal")
./tests/minimal/test.sh minimal

# Or check manually
docker logs minimal
docker exec minimal ps aux
docker exec minimal s6-rc -a list

# Clean up
docker compose down
```

### Existing Test Configurations

| File | Purpose |
|------|---------|
| `minimal.env` | Base container, all features disabled |
| `ssh-enabled.env` | SSH service with test key |
| `ui-disabled.env` | CLI-only mode |
| `ssh-and-ui.env` | Multiple services together |
| `all-optional-disabled.env` | All features explicitly false |
