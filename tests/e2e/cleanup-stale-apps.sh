#!/bin/bash
# cleanup-stale-apps.sh — Janitor that deletes leaked openclaw-e2e-* test apps.
#
# Run periodically (e.g. every 4 hours) or as part of CI cleanup.
# Deletes any App Platform app whose name starts with "openclaw-e2e-" and was
# created more than MAX_AGE_HOURS ago.
#
# Required env vars:
#   DOCTL_TOKEN  — DigitalOcean API token
#
# Optional env vars:
#   MAX_AGE_HOURS — Max age before cleanup (default: 2)
#   DRY_RUN       — If "true", list but don't delete
#
set -euo pipefail

MAX_AGE_HOURS="${MAX_AGE_HOURS:-2}"
DRY_RUN="${DRY_RUN:-false}"

if [ -z "${DOCTL_TOKEN:-}" ]; then
    echo "SKIP: DOCTL_TOKEN not set"
    exit 0
fi

export DIGITALOCEAN_ACCESS_TOKEN="$DOCTL_TOKEN"

echo "=== OpenClaw E2E App Janitor ==="
echo "  Max age: ${MAX_AGE_HOURS}h | Dry run: ${DRY_RUN}"
echo ""

# Get all apps as JSON
APPS_JSON=$(doctl apps list --output json 2>/dev/null || echo "[]")

# Current time in seconds since epoch
NOW=$(date +%s)
CUTOFF=$((NOW - MAX_AGE_HOURS * 3600))

CLEANED=0

# Filter for openclaw-e2e-* apps
echo "$APPS_JSON" | jq -r '.[] | select(.spec.name | startswith("openclaw-e2e-")) | "\(.id) \(.spec.name) \(.created_at)"' | while read -r APP_ID APP_NAME CREATED_AT; do
    # Parse creation time
    CREATED_EPOCH=$(date -d "$CREATED_AT" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$CREATED_AT" +%s 2>/dev/null || echo "0")

    if [ "$CREATED_EPOCH" -lt "$CUTOFF" ]; then
        AGE_HOURS=$(( (NOW - CREATED_EPOCH) / 3600 ))
        if [ "$DRY_RUN" = "true" ]; then
            echo "  [DRY RUN] Would delete: $APP_NAME ($APP_ID), age: ${AGE_HOURS}h"
        else
            echo "  Deleting: $APP_NAME ($APP_ID), age: ${AGE_HOURS}h"
            doctl apps delete "$APP_ID" --force 2>/dev/null || echo "    Warning: failed to delete $APP_ID"
            CLEANED=$((CLEANED + 1))
        fi
    else
        AGE_MIN=$(( (NOW - CREATED_EPOCH) / 60 ))
        echo "  Keeping: $APP_NAME ($APP_ID), age: ${AGE_MIN}m (< ${MAX_AGE_HOURS}h cutoff)"
    fi
done

echo ""
echo "Janitor complete. Cleaned: $CLEANED apps."
