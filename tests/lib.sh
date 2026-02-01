#!/bin/bash
# Shared test utilities for openclaw-appplatform tests

# Get project root from any test directory
get_project_root() {
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

PROJECT_ROOT="${PROJECT_ROOT:-$(get_project_root)}"

# Wait for container to be ready
# Usage: wait_for_container <container-name> [max-attempts]
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

# Wait for an s6 service to be up
# Usage: wait_for_service <container-name> <service-name> [max-attempts]
wait_for_service() {
    local container=$1
    local service=$2
    local max_attempts=${3:-30}
    local attempt=1

    echo "Waiting for $service service..."

    while [ $attempt -le $max_attempts ]; do
        if docker exec "$container" /command/s6-svstat "/run/service/$service" 2>/dev/null | grep -q "^up"; then
            echo "✓ $service service running"
            return 0
        fi
        echo "  Attempt $attempt/$max_attempts..."
        sleep 2
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
        sleep 2
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
