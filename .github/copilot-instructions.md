# Copilot Instructions for openclaw-appplatform

## Repository Overview
`openclaw-appplatform` is a Docker template for deploying OpenClaw on DigitalOcean App Platform. It wraps OpenClaw (installed via `pnpm add -g openclaw`) with s6-overlay service management, Tailscale networking, and Restic backup support.

Apps using this template with `deploy_on_push: true` automatically rebuild and redeploy when changes are pushed to `main`.

---

## CRITICAL RULES — READ BEFORE MAKING ANY CHANGES

### Golden Rules for Upgrades

1. **Make MINIMUM changes necessary.** Most upgrades need ONLY a Dockerfile version bump.
2. **NEVER modify rootfs/etc/services.d/openclaw/run** unless absolutely required by upstream breaking changes.
3. **NEVER add retry loops, polling, wait-for-service, or recovery code.** These create problems, not fix them.
4. **NEVER add config corruption recovery.** Fix the cause, not the symptom.
5. **Every jq write to openclaw.json MUST be followed by:** `chown openclaw:openclaw "$CONFIG_FILE"`
6. **Use `jq '.key //= "value"`** (set-if-missing) for new defaults, not unconditional set.
7. **NEVER modify test files (`tests/`) to make them pass.** Fix the application code instead. See "Test Integrity" section below.
8. **Read UPGRADE-AUTOMATION-CONTEXT.md** before making any upgrade-related changes.

### What Actually Went Wrong (2026.2.9 → 2026.3.11)

Previous upgrade attempts added:
- ❌ 32 lines of Tailscale FQDN detection + allowedOrigins patching → caused socket errors
- ❌ Config corruption recovery code → unnecessary workaround for the above
- ❌ Reinstall scripts → unnecessary workaround for pnpm store corruption
- ❌ Removing chown → caused permission denied errors

The correct solution was **4 targeted changes (+31 -10 lines)** across 4 files:
- ✅ Dockerfile version bump
- ✅ Config persistence logic (don't overwrite user settings)
- ✅ tools.profile default override (coding vs messaging)
- ✅ pnpm store backup exclusion

---

## When a Version Bump is Enough (90% of upgrades)

**Only change:** `ARG OPENCLAW_VERSION=X.Y.Z` in Dockerfile

**How to verify:**
1. All CI tests pass
2. Release notes contain no breaking changes
3. No new required config fields
4. No changes to config schema

**Then:** Open PR with just the Dockerfile change.

---

## When Template Changes Are Needed (10% of upgrades)

Read the release notes and check **ONLY** for these specific changes:

| Release note says... | Template change needed |
|---|---|---|
| Config field default changed | Add `jq '.field //= "value"'` in `20-setup-openclaw` |
| New required config field | Add to `openclaw.default.json` AND jq in `20-setup-openclaw` |
| New required env var | Add to persist_env_var block in `20-setup-openclaw` |
| Node.js version requirement | Update nvm install in `Dockerfile` |
| New system dependency | Add to apt-get install in `Dockerfile` |
| Breaking config schema change | Update `openclaw.default.json` |

---

## Files You Should NEVER Change

Unless the release notes explicitly require it:

- `rootfs/etc/services.d/openclaw/run`
- `rootfs/etc/services.d/tailscale/run`
- `rootfs/etc/cont-init.d/10-restore-state`
- `rootfs/etc/cont-init.d/00-setup-tailscale`

These are **proven working**. Previous attempts to modify them caused service failures.

---

## Files You May Need to Change (in order of likelihood)

1. **Dockerfile** (`OPENCLAW_VERSION`) — every upgrade
2. **rootfs/etc/cont-init.d/20-setup-openclaw** — when config defaults change
3. **rootfs/etc/openclaw/openclaw.default.json** — when new config fields needed
4. **rootfs/etc/digitalocean/backup.yaml** — rarely (new paths to exclude)

---

## Architecture — What Runs in the Container

```
Container starts as root
  └── s6-overlay init
       ├── cont-init.d/00-persist-env-vars     (env setup)
       ├── cont-init.d/00-setup-tailscale      (tailscale config)
       ├── cont-init.d/05-setup-restic          (backup config)
       ├── cont-init.d/06-restore-packages      (apt restore)
       ├── cont-init.d/10-restore-state          (restic restore)
       ├── cont-init.d/11-reinstall-brews        (homebrew restore)
       ├── cont-init.d/12-ssh-import-ids         (ssh keys)
       ├── cont-init.d/20-setup-openclaw    ← CONFIG GENERATION HAPPENS HERE
       ├── cont-init.d/99999-apply-permissions   (fix ownership)
       └── services.d/
            ├── openclaw/run     ← STARTS THE GATEWAY (runs as openclaw user)
            ├── tailscale/run    ← STARTS TAILSCALE
            ├── crond/run        ← STARTS CRON
            └── backup/run       ← STARTS RESTIC BACKUP (if configured)
```

### Critical rule: init scripts configure, run scripts execute

- **Init scripts** (`cont-init.d/`) handle all configuration, user setup, file generation
- **Run scripts** (`services.d/*/run`) just start the service — no config logic

---

## Key Files to Know

| File | Purpose | Change frequency |
|---|---|---|
| `Dockerfile` | Version, system deps, node/pnpm install | Every upgrade |
| `rootfs/etc/cont-init.d/20-setup-openclaw` | Config generation, env→config mapping | When config schema changes |
| `rootfs/etc/openclaw/openclaw.default.json` | Default config template | When new config fields needed |
| `rootfs/etc/services.d/openclaw/run` | Service startup script | Almost never |
| `rootfs/etc/digitalocean/backup.yaml` | Restic backup paths/exclusions | Rarely |
| `UPGRADE-AUTOMATION-CONTEXT.md` | Full upgrade history and lessons learned | After each upgrade |

---

## Test Infrastructure

Tests live in `tests/` with configs in `example_configs/`. CI builds the Docker image once, then runs each test script as a separate job.

### Existing Tests

| Test | What it verifies |
|---|---|
| `minimal/01-container.sh` | Container starts and is responsive |
| `minimal/02-gateway.sh` | Gateway node process is running |
| `minimal/03-ssh-disabled.sh` | SSH not running by default |
| `minimal/04-upgrade-verify.sh` | **Upgrade-specific checks** (see below) |
| `ssh-enabled/` | SSH service, keys, connectivity |
| `ui-disabled/` | Control UI disabled via env var |
| `persistence-enabled/` | Restic backup and restore |
| `all-optional-disabled/` | Everything optional is off |
| `e2e/deploy-and-test.sh` | **App Platform E2E** (deploy, verify, teardown) |
| `e2e/cleanup-stale-apps.sh` | Janitor for leaked E2E test apps |

### What 04-upgrade-verify.sh checks (Docker smoke tests)

✅ Version matches Dockerfile  
✅ Config is valid JSON  
✅ `tools.profile` is `coding`  
✅ Config owned by `openclaw` (not root)  
✅ Gateway auth mode is `token`  
✅ Gateway process running  
✅ Tailscale binary present  
✅ Gateway HTTP responds 200  
✅ Config writable by openclaw user  
✅ Channel plugins loaded (whatsapp, telegram, signal, discord)  
✅ Backup config valid  
✅ pnpm store excluded from backups  
✅ Telegram channel probe (if `TELEGRAM_BOT_TOKEN` set)  
✅ `openclaw doctor` completes  

### What e2e/deploy-and-test.sh checks (App Platform E2E)

Deploys the tested Docker image to App Platform as a real worker app, then:

✅ Deployment becomes ACTIVE  
✅ Config valid JSON + correct defaults (via `doctl apps console`)  
✅ Gateway process running + HTTP 200  
✅ Auth mode is token  
✅ Channel plugins loaded  
✅ Backup config valid  
✅ Telegram channel probe (if `TELEGRAM_BOT_TOKEN` set)  

Gracefully skipped if `DOCTL_TOKEN` is not configured (e.g., fork PRs).

### CI Secrets

| Secret | Purpose | Required? |
|---|---|---|
| `DIGITALOCEAN_ACCESS_TOKEN` | Deploy/delete test apps on App Platform via doctl | For E2E tests |
| `DO_SPACES_ACCESS_KEY_ID` | Ephemeral Spaces buckets for persistence tests | For persistence tests |
| `DO_SPACES_SECRET_ACCESS_KEY` | Paired with above | For persistence tests |
| `GRADIENT_API_KEY` | AI model provider key (injected into config) | For AI features |
| `GHCR_TOKEN` | Push images to GHCR (build-push workflow) | For manual GHCR push |
| `TAILSCALE_AUTH_TOKEN` | Tailscale auth key for networking tests | For Tailscale tests |
| `TELEGRAM_BOT_TOKEN` | Telegram channel status probe | **New — needs to be added** |

All secrets use **GitHub repo/org secrets** (not Vault). Tests gracefully skip when secrets are unavailable.

---

## Common Workflows

### Upgrading OpenClaw (Automated)

The **openclaw-upgrade-check.yml** workflow runs every Monday (2pm UTC):

1. **check-version** — Compares `OPENCLAW_VERSION` in Dockerfile against latest stable release. Checks for upstream regressions.
2. **docker-tests** — Bumps Dockerfile, builds image, starts container, runs `04-upgrade-verify.sh` (14 checks).
3. **push-e2e-image** — Pushes tested image to GHCR with `e2e-{run_id}` tag.
4. **app-platform-e2e** — Deploys image to App Platform via `doctl apps create`, runs live health checks, tears down. Skipped if `DOCTL_TOKEN` not set.
5. **open-pr** — Creates upgrade PR with test results, release notes, and regression warnings.
6. **open-issue** — If any test fails, creates issue with test output and tags `@copilot` to trigger the Copilot agent auto-fix flow.

Can be triggered manually via `workflow_dispatch`, with optional `force_version` input.

### Upgrading OpenClaw (Manual)

```bash
# 1. Update Dockerfile
vim Dockerfile  # Change OPENCLAW_VERSION

# 2. Build locally
docker build -t openclaw-test:local .

# 3. Run container
docker run -d --name openclaw-test \
  -e OPENCLAW_GATEWAY_TOKEN=test-token \
  openclaw-test:local

# 4. Run upgrade verification
chmod +x tests/minimal/04-upgrade-verify.sh
./tests/minimal/04-upgrade-verify.sh openclaw-test

# 5. Cleanup
docker rm -f openclaw-test
```

### Investigating Failed Upgrades

When the automated workflow creates an issue:

1. **Check the workflow run logs** — what test failed?
2. **Read the release notes** — linked in the PR body
3. **Check for known regressions** — listed in the PR if found
4. **Common failure causes:**
   - New required config field → update `20-setup-openclaw` and `openclaw.default.json`
   - Config schema changed → update default config template
   - New env var required → add to persist_env_var block
   - Dependency version conflict → update Dockerfile apt-get or nvm install

### Skipping a Version (Like we skipped 2026.3.13)

If a version has a known regression:

1. Close the automated PR
2. Comment on the issue with the upstream bug link
3. Wait for the bug to be fixed upstream
4. The next weekly check will pick up the fixed version

**Example:** 2026.3.13 had a WebSocket handshake timeout bug (openclaw/openclaw#46892). We stayed on 2026.3.11 until the fix shipped.

---

## Common Mistakes to Avoid

### ❌ DON'T: Add Tailscale detection to openclaw/run

```bash
# WRONG — causes socket errors
TAILSCALE_FQDN=$(tailscale status --json | jq -r '.Self.DNSName')
jq ".gateway.allowedOrigins += [\"https://${TAILSCALE_FQDN}\"]" "$CONFIG_FILE"
```

**Why it fails:** `tailscaled` may not be running when `openclaw/run` starts.

**Correct approach:** Let users configure this via env vars in the init script.

### ❌ DON'T: Overwrite user config unconditionally

```bash
# WRONG — loses user settings on every restart
cp "$DEFAULT_CONFIG" "$CONFIG_FILE"
```

**Correct approach:**
```bash
# Set defaults only if config doesn't exist or is invalid
if [ -f "$CONFIG_FILE" ] && jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
  echo "Existing config found; preserving user settings"
else
  cp "$DEFAULT_CONFIG" "$CONFIG_FILE"
fi
```

### ❌ DON'T: Write config files as root without chown

```bash
# WRONG — service runs as openclaw user, can't read config
jq '.tools.profile = "coding"' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
```

**Correct approach:**
```bash
jq '.tools.profile //= "coding"' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
chown openclaw:openclaw "$CONFIG_FILE"  # REQUIRED
```

---

## Test Integrity — NEVER Modify Tests to Make Them Pass

**Tests exist to verify the application behaves correctly. If a test fails, fix the application — not the test.**

### ❌ NEVER do this

```bash
# WRONG — changes the test to avoid a FAIL by making the assertion weaker
- PNPM_EXCLUDED=$(docker exec "$CONTAINER" grep -c 'pnpm' /etc/digitalocean/backup.yaml || echo "0")
- if [ "$PNPM_EXCLUDED" -ge 1 ]; then
+ if docker exec "$CONTAINER" grep -q 'pnpm' /etc/digitalocean/backup.yaml; then
```

Even if the test had a bash bug, the correct fix is to fix the bash bug **only** — not to change what the test checks or weaken its assertion.

### ✅ Always do this instead

When a test FAILs, trace it to the root cause in the application:

| Test failure | Root cause | Fix location |
|---|---|---|
| `tools.profile is 'null'` | Default changed upstream in 2026.3.x | Add `jq '.tools.profile //= "coding"'` in `20-setup-openclaw` AND add `"tools": {"profile": "coding"}` to `openclaw.default.json` |
| `pnpm store may not be excluded` | Missing backup exclusion | Add `.local/share/pnpm/store` to `backup.yaml` exclude list |
| `Config owned by root` | Missing chown after jq write | Add `chown openclaw:openclaw "$CONFIG_FILE"` after every jq mutation |
| `Auth mode: not token` | Config overwrite lost token | Fix config preservation logic in `20-setup-openclaw` |

### How to trace a test failure to the fix

1. Read the exact FAIL message from the test output in the issue
2. Find the failing assertion in `tests/minimal/04-upgrade-verify.sh` — understand what it checks
3. Identify **which application file** controls that behavior (see table above)
4. Apply the fix to **that application file**, not to the test
5. Rebuild and re-run the test to confirm it passes

### PR review rule

**Always verify the "Files changed" tab matches the PR description.** Copilot's PR descriptions can describe changes that were never actually committed. If the description says `20-setup-openclaw` was changed but it doesn't appear in "Files changed", the fix is incomplete.

---

## Backup & Restore (Restic)

Users can enable Restic backups by setting env vars. The backup config is in `rootfs/etc/digitalocean/backup.yaml`.

**CRITICAL:** Exclude pnpm global store from backups:
```yaml
exclude:
  - ".local/share/pnpm/global"
  - ".local/share/pnpm/store"
```

**Why:** Version mismatches after upgrades cause `openclaw` to fail to start.

---

## Environment Variables → Config Mapping

The init script `20-setup-openclaw` maps environment variables to config fields. Common mappings:

| Env Var | Config Path | Default |
|---|---|---|
| `OPENCLAW_GATEWAY_TOKEN` | `.gateway.auth.token` | (required) |
| `OPENCLAW_GATEWAY_MODE` | `.gateway.mode` | `local` |
| `OPENCLAW_TOOLS_PROFILE` | `.tools.profile` | `coding` |
| `OPENCLAW_UI_ENABLED` | `.ui.enabled` | `true` |

When a new env var is added, it must be persisted via the `persist_env_var` function.

---

## Debugging Container Issues

```bash
# Check init script logs
docker logs <container-name> 2>&1 | grep cont-init.d

# Check service logs
docker logs <container-name> 2>&1 | grep s6-rc

# Exec into container as openclaw user
docker exec -u openclaw -it <container-name> bash

# Check config
docker exec <container-name> cat /data/.openclaw/openclaw.json | jq

# Check ownership
docker exec <container-name> ls -la /data/.openclaw/

# Check gateway process
docker exec <container-name> pgrep -fa openclaw-gateway

# Test gateway HTTP
docker exec <container-name> curl -v http://127.0.0.1:18789/
```

---

## Release Monitoring

This template is actively used in production. Changes require careful rollout:

1. **Test locally** with the upgrade verification script
2. **Open PR** (automated by workflow if tests pass)
3. **Review release notes** for breaking changes
4. **Merge to main** after human review
5. **Monitor app builds** — apps with `deploy_on_push: true` rebuild automatically
6. **Check error rates** in monitoring dashboards

---

## Known Issues & Workarounds

### Issue: WebSocket handshake timeout (2026.3.13)

**Symptom:** `openclaw gateway health` CLI fails with timeout  
**Affected:** 2026.3.13 only  
**Workaround:** Stay on 2026.3.11 until openclaw/openclaw#49049 is merged  
**Status:** Tracked in openclaw/openclaw#46892  

### Issue: Config corruption after manual edits

**Symptom:** Gateway fails to start after user edits config via SSH  
**Cause:** Invalid JSON written to `openclaw.json`  
**Prevention:** Init script validates JSON before accepting existing config  
**Recovery:** Container restart regenerates config from default template  

---

## How to Update This Document

After every successful upgrade:

1. Update `UPGRADE-AUTOMATION-CONTEXT.md` with any new lessons learned
2. Update this file if new config fields, env vars, or files were added
3. Document any new workarounds or known issues
4. Update the test suite if new verification checks are needed

---

## Summary: Agent Decision Tree

```
New OpenClaw version available?
│
├─ NO → Wait for next weekly check
│
└─ YES → Check release notes
         │
         ├─ Just bug fixes? → Bump Dockerfile only
         │
         ├─ New config field? → Update 20-setup-openclaw + default.json
         │
         ├─ Breaking change? → Update template + tests + docs
         │
         └─ Known regression? → Skip version, wait for fix
```

**Remember:** The automated workflow handles 90% of upgrades. Agents only need to handle the 10% where template changes are required.

---

## App Platform E2E Testing

### How it works

The E2E test (`tests/e2e/deploy-and-test.sh`) deploys the CI-built Docker image as a real App Platform worker:

1. Renders `tests/e2e/app-spec-template.yaml` with run-specific values (image tag, token, app name)
2. Creates the app via `doctl apps create --spec`
3. Polls deployment status until `ACTIVE` (timeout: 10 min)
4. Runs health checks via `doctl apps console` (config, gateway, plugins, backup)
5. Deletes the app via `doctl apps delete`
6. A `trap cleanup EXIT` ensures the app is always deleted, even on failure

### Janitor

`tests/e2e/cleanup-stale-apps.sh` finds and deletes any `openclaw-e2e-*` apps older than 2 hours. Runs as part of the workflow cleanup and can be run manually:

```bash
DOCTL_TOKEN=<token> MAX_AGE_HOURS=2 ./tests/e2e/cleanup-stale-apps.sh
```

### Telegram channel testing

If `TELEGRAM_BOT_TOKEN` is set:
- Docker tests inject the token into the container config and run `openclaw channels status`
- E2E tests do the same via `doctl apps console`
- Verifies the full plugin loading → Telegram Bot API authentication pipeline

**One-time setup:** Create a bot via @BotFather, store the token as a GitHub secret. Send `/start` to the bot from a real Telegram account to initialize the chat.
