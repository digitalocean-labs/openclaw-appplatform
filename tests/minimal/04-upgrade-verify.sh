#!/bin/bash
# Test: OpenClaw upgrade verification
# Verifies version, config defaults, ownership, gateway, plugins, and services.
#
# Required: CONTAINER name as $1
# Optional env vars:
#   TELEGRAM_BOT_TOKEN  — if set, verifies Telegram channel connects
#   SKIP_GATEWAY_HTTP   — if "true", skip the HTTP 200 check (for headless E2E)
set -e

CONTAINER=${1:?Usage: $0 <container-name>}
source "$(dirname "$0")/../lib.sh"

PASS=0
FAIL=0
WARN=0

pass() { echo "✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
warn() { echo "WARN: $1"; WARN=$((WARN + 1)); }

echo "=== OpenClaw Upgrade Verification ==="
echo ""

wait_for_container "$CONTAINER" 60

# ---------------------------------------------------------------------------
# 1. Version matches Dockerfile
# ---------------------------------------------------------------------------
EXPECTED_VERSION=$(grep 'OPENCLAW_VERSION=' "$(get_project_root)/Dockerfile" | head -1 | sed 's/.*=//')
ACTUAL_VERSION=$(docker exec "$CONTAINER" su - openclaw -c "openclaw --version 2>/dev/null" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
if [ "$ACTUAL_VERSION" = "$EXPECTED_VERSION" ]; then
    pass "Version: $ACTUAL_VERSION"
else
    fail "Expected version $EXPECTED_VERSION, got $ACTUAL_VERSION"
fi

# ---------------------------------------------------------------------------
# 2. Config is valid JSON
# ---------------------------------------------------------------------------
if docker exec "$CONTAINER" jq empty /data/.openclaw/openclaw.json 2>/dev/null; then
    pass "Config is valid JSON"
else
    fail "Config is invalid JSON"
fi

# ---------------------------------------------------------------------------
# 3. tools.profile is coding
# ---------------------------------------------------------------------------
PROFILE=$(docker exec "$CONTAINER" jq -r '.tools.profile' /data/.openclaw/openclaw.json 2>/dev/null)
if [ "$PROFILE" = "coding" ]; then
    pass "tools.profile: coding"
else
    fail "tools.profile is '$PROFILE' (expected 'coding')"
fi

# ---------------------------------------------------------------------------
# 4. Config owned by openclaw user
# ---------------------------------------------------------------------------
OWNER=$(docker exec "$CONTAINER" stat -c '%U' /data/.openclaw/openclaw.json 2>/dev/null)
if [ "$OWNER" = "openclaw" ]; then
    pass "Config owned by openclaw"
else
    fail "Config owned by '$OWNER' (expected 'openclaw')"
fi

# ---------------------------------------------------------------------------
# 5. Gateway auth mode is token
# ---------------------------------------------------------------------------
AUTH=$(docker exec "$CONTAINER" jq -r '.gateway.auth.mode' /data/.openclaw/openclaw.json 2>/dev/null)
if [ "$AUTH" = "token" ]; then
    pass "Auth mode: token"
else
    fail "Auth mode is '$AUTH' (expected 'token')"
fi

# ---------------------------------------------------------------------------
# 6. Gateway process running
# ---------------------------------------------------------------------------
if docker exec "$CONTAINER" pgrep -f "openclaw-gateway" >/dev/null 2>&1; then
    pass "Gateway process running"
else
    fail "Gateway process not running"
fi

# ---------------------------------------------------------------------------
# 7. Tailscale binary exists
# ---------------------------------------------------------------------------
if docker exec "$CONTAINER" which tailscale >/dev/null 2>&1; then
    pass "Tailscale binary present"
else
    fail "Tailscale binary missing"
fi

# ---------------------------------------------------------------------------
# 8. Gateway HTTP responds (up to 3 min cold start)
# ---------------------------------------------------------------------------
if [ "${SKIP_GATEWAY_HTTP:-false}" = "true" ]; then
    warn "Gateway HTTP check skipped (SKIP_GATEWAY_HTTP=true)"
else
    echo "Waiting for gateway HTTP..."
    CODE="000"
    for i in $(seq 1 36); do
        CODE=$(docker exec "$CONTAINER" curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:18789/ 2>/dev/null || echo "000")
        [ "$CODE" = "200" ] && break
        sleep 5
    done
    if [ "$CODE" = "200" ]; then
        pass "Gateway HTTP: 200"
    else
        fail "Gateway HTTP not responding (code: $CODE)"
    fi
fi

# ---------------------------------------------------------------------------
# 9. Config writable by openclaw user
# ---------------------------------------------------------------------------
docker exec "$CONTAINER" su - openclaw -c \
    "jq '.test_marker = \"upgrade-test\"' /data/.openclaw/openclaw.json > /tmp/oc.json && cp /tmp/oc.json /data/.openclaw/openclaw.json" 2>/dev/null
MARKER=$(docker exec "$CONTAINER" jq -r '.test_marker' /data/.openclaw/openclaw.json 2>/dev/null)
if [ "$MARKER" = "upgrade-test" ]; then
    pass "Config writable by openclaw user"
else
    fail "Config not writable by openclaw user"
fi

# ---------------------------------------------------------------------------
# 10. Channel plugins loaded in config
# ---------------------------------------------------------------------------
PLUGINS=$(docker exec "$CONTAINER" jq -r '.plugins.entries | keys | sort | join(",")' /data/.openclaw/openclaw.json 2>/dev/null || echo "")
EXPECTED_PLUGINS="discord,signal,telegram,whatsapp"
if [ "$PLUGINS" = "$EXPECTED_PLUGINS" ]; then
    pass "Channel plugins loaded: $PLUGINS"
else
    warn "Expected plugins '$EXPECTED_PLUGINS', got '$PLUGINS'"
fi

# ---------------------------------------------------------------------------
# 11. Backup service configuration (check backup.yaml parseable)
# ---------------------------------------------------------------------------
if docker exec "$CONTAINER" yq eval '.repository' /etc/digitalocean/backup.yaml >/dev/null 2>&1; then
    pass "Backup config (backup.yaml) is valid"
else
    warn "Backup config not parseable (may be expected if yq missing)"
fi

# ---------------------------------------------------------------------------
# 12. pnpm global store excluded from backups
# ---------------------------------------------------------------------------
if docker exec "$CONTAINER" grep -q 'pnpm' /etc/digitalocean/backup.yaml 2>/dev/null; then
    pass "pnpm store excluded from backups"
else
    warn "pnpm store may not be excluded from backups"
fi

# ---------------------------------------------------------------------------
# 13. Telegram channel probe (optional — requires TELEGRAM_BOT_TOKEN)
# ---------------------------------------------------------------------------
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
    echo "Probing Telegram channel..."
    # Inject bot token into config and probe
    docker exec "$CONTAINER" bash -c "
        jq '.plugins.entries.telegram.token = \"${TELEGRAM_BOT_TOKEN}\"' /data/.openclaw/openclaw.json > /tmp/oc_tg.json \
        && cp /tmp/oc_tg.json /data/.openclaw/openclaw.json \
        && chown openclaw:openclaw /data/.openclaw/openclaw.json
    " 2>/dev/null
    # Restart gateway to pick up new config
    docker exec "$CONTAINER" /command/s6-svc -r /run/service/openclaw 2>/dev/null || true
    sleep 10
    # Check channel status
    TG_STATUS=$(docker exec "$CONTAINER" su - openclaw -c "openclaw channels status 2>/dev/null" | grep -i telegram || echo "")
    if echo "$TG_STATUS" | grep -qi "connected\|available\|ok"; then
        pass "Telegram channel connected"
    else
        warn "Telegram channel status: $TG_STATUS (may need manual /start)"
    fi
else
    echo "SKIP: Telegram channel probe (TELEGRAM_BOT_TOKEN not set)"
fi

# ---------------------------------------------------------------------------
# 14. openclaw doctor completes
# ---------------------------------------------------------------------------
if docker exec "$CONTAINER" su - openclaw -c "openclaw doctor 2>/dev/null" | grep -qi "complete\|ok\|pass"; then
    pass "openclaw doctor completes"
else
    warn "openclaw doctor did not complete (may need longer startup)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Upgrade Verification Results ==="
echo "  Passed:   $PASS"
echo "  Failed:   $FAIL"
echo "  Warnings: $WARN"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo "=== UPGRADE VERIFICATION FAILED ($FAIL failures) ==="
    exit 1
else
    echo "=== All upgrade verification tests passed ✅ ==="
    exit 0
fi
