# OpenClaw App Platform Deployment

## Overview

This repository contains the Docker configuration and deployment templates for running [OpenClaw](https://github.com/openclaw/openclaw) on DigitalOcean App Platform with Tailscale networking.

## Quick Start

```bash
cp .env.example .env           # Configure environment variables
make rebuild                   # Build and start container
make logs                      # Follow container logs
make shell                     # Shell into running container
```

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
- `00-persist-env-vars` - Persists environment variables for s6
- `00-setup-tailscale` - Configures Tailscale networking (if enabled)
- `05-setup-restic` - Initializes Restic repository and exports environment variables
- `06-restore-packages` - Restores dpkg package list from backup
- `10-restore-state` - Restores application state from Restic snapshots
- `11-reinstall-brews` - Reinstalls Homebrew packages from backup (if Homebrew installed)
- `12-ssh-import-ids` - Imports SSH keys from GitHub (if GITHUB_USERNAME set)
- `20-setup-openclaw` - Builds openclaw.json from environment variables
- `99999-apply-permissions` - Applies final file permissions

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

Tailscale is required for networking. The gateway binds to `127.0.0.1:18789` and uses Tailscale serve mode to expose port 443 on your tailnet.

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

Optional DO Spaces backup via [Restic](https://restic.net/) when `ENABLE_SPACES=true`.

**How it works:**

- Incremental, encrypted snapshots to DigitalOcean Spaces (S3-compatible)
- Backup runs every 30s; prune runs hourly
- `10-restore-state` restores latest snapshots on container start

**What gets backed up:** `/etc`, `/root`, `/data/.openclaw`, `/data/tailscale`, `/home`

**Required env vars:** `RESTIC_SPACES_ACCESS_KEY_ID`, `RESTIC_SPACES_SECRET_ACCESS_KEY`, `RESTIC_SPACES_ENDPOINT`, `RESTIC_SPACES_BUCKET`, `RESTIC_PASSWORD`

**Customizing:** Edit `rootfs/etc/digitalocean/backup.yaml` to change intervals, paths, excludes, or retention policy.

## Testing

CI runs on push/PR to main via GitHub Actions (`.github/workflows/test.yml`):

- Builds the Docker image
- Starts container with features disabled
- Verifies container stays running

Run locally with `make rebuild` to test changes before pushing.

## Gotchas

- **Use `openclaw` wrapper in console sessions** - The wrapper in `/usr/local/bin/openclaw` runs commands as the correct user with proper environment. Running the binary directly as root won't work.
- **Service restarts**: Use `/command/s6-svc -r /run/service/<name>` to restart services (openclaw, ngrok, tailscale, etc.)
- **See CHEATSHEET.md** for detailed command reference and troubleshooting

## Development

Do not push code changes and then trigger a deployment when trying to develop. Make code changes inside the container and restart the OpenClaw service to iterate quickly:

```bash
make shell                                    # Enter container
# Make your changes...
/command/s6-svc -r /run/service/openclaw      # Restart service
```
