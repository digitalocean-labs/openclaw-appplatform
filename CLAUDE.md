# OpenClaw App Platform Deployment

## Overview

This repository contains the Docker configuration and deployment templates for running [OpenClaw](https://github.com/openclaw/openclaw) on DigitalOcean App Platform with Tailscale networking.

## Key Files

- `Dockerfile` - Builds image with Ubuntu Noble, s6-overlay, Tailscale, Restic, Homebrew, pnpm, and openclaw
- `app.yaml` - App Platform service configuration (for reference, uses worker for Tailscale)
- `.do/deploy.template.yaml` - App Platform worker configuration (recommended)
- `rootfs/etc/openclaw/openclaw.default.json` - Base gateway configuration template
- `rootfs/etc/digitalocean/backup.yaml` - Restic backup configuration (paths, intervals, retention policy)
- `tailscale` - Wrapper script to inject socket path for tailscale CLI
- `rootfs/` - Overlay directory for custom files and s6 services

## s6-overlay Init System

The container uses [s6-overlay](https://github.com/just-containers/s6-overlay) for process supervision:

**Initialization scripts** (`rootfs/etc/cont-init.d/`):
- `00-setup-tailscale` - Configures Tailscale networking (if enabled)
- `05-setup-restic` - Initializes Restic repository and exports environment variables
- `06-restore-packages` - Restores dpkg package list from backup
- `10-restore-state` - Restores application state from Restic snapshots
- `15-reinstall-brews` - Reinstalls Homebrew packages from backup (if Homebrew installed)
- `50-generate-config` - Builds openclaw.json from environment variables

**Services** (`rootfs/etc/services.d/`):
- `tailscale/` - Tailscale daemon (if TAILSCALE_ENABLE=true)
- `openclaw/` - OpenClaw gateway
- `ngrok/` - ngrok tunnel (if ENABLE_NGROK=true)
- `sshd/` - SSH server (if SSH_ENABLE=true)
- `backup/` - Periodic Restic backup service (if ENABLE_SPACES=true)
- `prune/` - Periodic Restic snapshot cleanup (if ENABLE_SPACES=true)
- `crond/` - Cron daemon for scheduled tasks

Users can add custom init scripts (prefix with `30-` or higher) and custom services.

## Networking

Tailscale is required for networking. The gateway binds to loopback and uses Tailscale serve mode for access via your tailnet.

Required environment variables:
- `TS_AUTHKEY` - Tailscale auth key

## Configuration

All gateway settings are driven by the config file (`openclaw.json`). The init script dynamically builds the config based on environment variables:

- Tailscale serve mode for networking
- Gradient AI provider (if `GRADIENT_API_KEY` set)

## Gradient AI Integration

Set `GRADIENT_API_KEY` to enable DigitalOcean's serverless AI inference with models:
- Llama 3.3 70B Instruct
- Claude 4.5 Sonnet / Opus 4.5
- DeepSeek R1 Distill Llama 70B

## Persistence

Optional DO Spaces backup via [Restic](https://restic.net/):

**Backup System:**
- Uses Restic for incremental, encrypted snapshots to DigitalOcean Spaces (S3-compatible)
- Backup service runs continuously, creating snapshots every 30 seconds (configurable via `backup.yaml`)
- Prune service runs hourly to remove old snapshots and optimize storage
- Repository is automatically initialized on first run

**What Gets Backed Up:**
- `/etc` - System configuration
- `/root` - Root user home directory
- `/data/.openclaw` - OpenClaw state (config, sessions, agents, cron)
- `/data/tailscale` - Tailscale connection state
- `/home` - User home directories (includes Homebrew packages)

**Restore on Startup:**
- `10-restore-state` init script runs on container start
- Restores latest snapshot for each path from Restic repository
- Fixes file ownership (openclaw user) after restore
- Skips restore if no snapshots found (first run)

**Configuration:**
- Repository URL: `s3:<endpoint>/<bucket>/<hostname>/restic`
- Backup paths and intervals defined in `/etc/digitalocean/backup.yaml`
- Encrypted with `RESTIC_PASSWORD`
- Access via Spaces credentials (`RESTIC_SPACES_ACCESS_KEY_ID`, `RESTIC_SPACES_SECRET_ACCESS_KEY`)

## Customizing Backup Configuration

The backup system is configured via `/etc/digitalocean/backup.yaml`:

```yaml
# Repository location (S3-compatible, variables expanded at runtime)
repository: "s3:${RESTIC_SPACES_ENDPOINT}/${RESTIC_SPACES_BUCKET}/${RESTIC_HOST}/restic"

# Backup paths (order matters for restore)
paths:
  - path: /etc
  - path: /data/.openclaw
    exclude:
      - "*.lock"
      - "*.pid"

# Intervals
backup_interval_seconds: 30  # Backup frequency
prune_interval_seconds: 3600 # Prune frequency (1 hour)

# Retention policy
retention:
  keep_last: 10      # Keep last 10 snapshots
  keep_hourly: 48    # Keep 48 hourly snapshots
  keep_daily: 30     # Keep 30 daily snapshots
  keep_weekly: 8     # Keep 8 weekly snapshots
  keep_monthly: 6    # Keep 6 monthly snapshots
```

To customize, add your own `rootfs/etc/digitalocean/backup.yaml` and rebuild the image.

## Development

It's a general rule, do not push code change and then trigger a deployment when trying to develop. It's always better to make the code changes inside the container and then restart the OpenClaw service. That way we can iterate really fast.
