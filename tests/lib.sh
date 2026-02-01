#!/bin/bash
# Shared test utilities for openclaw-appplatform tests

# Get project root from any test directory
get_project_root() {
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

PROJECT_ROOT="${PROJECT_ROOT:-$(get_project_root)}"

# Switch to a test config while preserving secrets from current .env or environment
# Usage: switch_config <config-name>
switch_config() {
    local config=$1
    local env_file="$PROJECT_ROOT/.env"
    local config_file="$PROJECT_ROOT/example_configs/${config}.env"

    if [ ! -f "$config_file" ]; then
        echo "error: Config file not found: $config_file"
        return 1
    fi

    # Save secrets from current .env (KEY, SECRET, PASSWORD, TOKEN, AUTHKEY, plus RESTIC_SPACES_*)
    local secrets=""
    if [ -f "$env_file" ]; then
        secrets=$(grep -E '^([A-Z_]*(KEY|SECRET|PASSWORD|TOKEN|AUTHKEY|KEY_ID)=|RESTIC_SPACES_)' "$env_file" 2>/dev/null || true)
    fi

    # Copy config
    cp "$config_file" "$env_file"

    # Append secrets from .env
    if [ -n "$secrets" ]; then
        echo "" >> "$env_file"
        echo "$secrets" >> "$env_file"
    fi

    # Also append secrets from environment variables (for CI)
    {
        [ -n "$RESTIC_SPACES_ACCESS_KEY_ID" ] && echo "RESTIC_SPACES_ACCESS_KEY_ID=$RESTIC_SPACES_ACCESS_KEY_ID"
        [ -n "$RESTIC_SPACES_SECRET_ACCESS_KEY" ] && echo "RESTIC_SPACES_SECRET_ACCESS_KEY=$RESTIC_SPACES_SECRET_ACCESS_KEY"
        [ -n "$RESTIC_SPACES_ENDPOINT" ] && echo "RESTIC_SPACES_ENDPOINT=$RESTIC_SPACES_ENDPOINT"
        [ -n "$RESTIC_SPACES_BUCKET" ] && echo "RESTIC_SPACES_BUCKET=$RESTIC_SPACES_BUCKET"
        [ -n "$RESTIC_PASSWORD" ] && echo "RESTIC_PASSWORD=$RESTIC_PASSWORD"
    } >> "$env_file"
}

# Wait for container to be ready (including s6-overlay init)
# Usage: wait_for_container <container-name> [max-attempts]
wait_for_container() {
    local container=$1
    local max_attempts=${2:-30}
    local attempt=1

    echo "Waiting for container $container to be ready..."

    # First wait for container to accept commands
    while [ $attempt -le $max_attempts ]; do
        if docker exec "$container" true 2>/dev/null; then
            break
        fi
        echo "  Attempt $attempt/$max_attempts..."
        sleep 0.5
        attempt=$((attempt + 1))
    done

    if [ $attempt -gt $max_attempts ]; then
        echo "error: Container did not become ready"
        return 1
    fi

    # Wait for s6 init to complete (crond service must be up - starts after all init scripts)
    echo "✓ Container is responsive (waiting for init to complete...)"
    local init_attempts=0
    local max_init_attempts=60  # 60 * 5s = 300s max
    while [ $init_attempts -lt $max_init_attempts ]; do
        # Check if crond service exists and is up (always enabled, starts after init)
        if docker exec "$container" /command/s6-svstat /run/service/crond 2>/dev/null | grep -q "^up"; then
            echo "✓ s6 init complete (crond up)"
            return 0
        fi
        sleep 5
        init_attempts=$((init_attempts + 1))
        echo "  Waiting for s6 init... ($((init_attempts * 5))s)"
        # Show recent logs every 10 attempts
        if [ $((init_attempts % 10)) -eq 0 ]; then
            echo "  --- Recent container logs ---"
            docker logs --tail 3 "$container" 2>&1 | sed 's/^/  /'
        fi
    done

    echo "error: s6 init did not complete"
    echo "--- Container logs ---"
    docker logs --tail 20 "$container" 2>&1
    return 1
}

# Wait for an s6 service to be up
# Usage: wait_for_service <container-name> <service-name> [max-attempts]
wait_for_service() {
    local container=$1
    local service=$2
    local max_attempts=${3:-30}
    local attempt=1

    echo "Waiting for $service service..."

    while [ $attempt -le $max_attempts ]; do
        # Check if service is supervised
        if docker exec "$container" /command/s6-svok "/run/service/$service" 2>/dev/null; then
            # Check if service is actually up (not just supervised)
            local status
            status=$(docker exec "$container" /command/s6-svstat "/run/service/$service" 2>/dev/null || echo "down")
            if echo "$status" | grep -q "^up"; then
                echo "✓ $service service running"
                return 0
            fi
        fi
        echo "  Attempt $attempt/$max_attempts..."
        sleep 0.5
        attempt=$((attempt + 1))
    done

    echo "error: $service service did not start"
    docker exec "$container" /command/s6-svstat "/run/service/$service" 2>&1 || true
    return 1
}

# Wait for a process to be running
# Usage: wait_for_process <container-name> <process-name> [max-attempts]
wait_for_process() {
    local container=$1
    local process=$2
    local max_attempts=${3:-5}
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if docker exec "$container" pgrep -x "$process" >/dev/null 2>&1; then
            echo "✓ $process process running"
            return 0
        fi
        if [ $attempt -eq $max_attempts ]; then
            return 1
        fi
        sleep 0.5
        attempt=$((attempt + 1))
    done
    return 1
}

# Restart container using docker compose
# Usage: restart_container <container-name>
restart_container() {
    local container=$1

    echo "Restarting container..."
    docker compose -f "$PROJECT_ROOT/compose.yaml" down
    docker compose -f "$PROJECT_ROOT/compose.yaml" up -d

    wait_for_container "$container"
}

# Check that a process is NOT running
# Usage: assert_process_not_running <container-name> <process-name>
assert_process_not_running() {
    local container=$1
    local process=$2

    if docker exec "$container" pgrep -x "$process" >/dev/null 2>&1; then
        echo "error: $process running but should not be"
        return 1
    fi
    echo "✓ $process not running (as expected)"
    return 0
}

# Check that a process IS running
# Usage: assert_process_running <container-name> <process-name>
assert_process_running() {
    local container=$1
    local process=$2

    if ! docker exec "$container" pgrep -x "$process" >/dev/null 2>&1; then
        echo "error: $process not running but should be"
        return 1
    fi
    echo "✓ $process running"
    return 0
}

# Check that an s6 service is up (supervised and running)
# Usage: assert_service_up <container-name> <service-name>
assert_service_up() {
    local container=$1
    local service=$2

    # First check if supervised
    if ! docker exec "$container" /command/s6-svok "/run/service/$service" 2>/dev/null; then
        echo "error: $service service not supervised but should be"
        return 1
    fi

    # Then check if actually up
    local status
    status=$(docker exec "$container" /command/s6-svstat "/run/service/$service" 2>/dev/null || echo "down")
    if ! echo "$status" | grep -q "^up"; then
        echo "error: $service service supervised but not up"
        echo "  status: $status"
        return 1
    fi
    echo "✓ $service service up"
    return 0
}

# Check that an s6 service is not running (either doesn't exist or is down)
# Usage: assert_service_down <container-name> <service-name>
assert_service_down() {
    local container=$1
    local service=$2

    # If service directory doesn't exist, it's down
    if ! docker exec "$container" test -d "/run/service/$service" 2>/dev/null; then
        echo "✓ $service service not present (as expected)"
        return 0
    fi

    # Service directory exists, check if it's down (not "up")
    local status
    status=$(docker exec "$container" /command/s6-svstat "/run/service/$service" 2>/dev/null || echo "down")
    if echo "$status" | grep -q "^up"; then
        echo "error: $service service is up but should not be"
        echo "  status: $status"
        return 1
    fi
    echo "✓ $service service down (as expected)"
    return 0
}
