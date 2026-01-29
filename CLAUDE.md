# Moltbot App Platform Deployment

## Overview

This repository contains the Docker configuration and deployment templates for running [Moltbot](https://github.com/moltbot/moltbot) on DigitalOcean App Platform with Tailscale networking.

## Key Files

- `Dockerfile` - Builds image with Ubuntu Noble, s6-overlay, Tailscale, Homebrew, pnpm, and moltbot
- `app.yaml` - App Platform service configuration (for reference, uses worker for Tailscale)
- `.do/deploy.template.yaml` - App Platform worker configuration (recommended)
- `litestream.yml` - SQLite replication config for persistence via DO Spaces
- `moltbot.default.json` - Base gateway configuration
- `tailscale` - Wrapper script to inject socket path for tailscale CLI
- `rootfs/` - Overlay directory for custom files and s6 services

## s6-overlay Init System

The container uses [s6-overlay](https://github.com/just-containers/s6-overlay) for process supervision:

**Initialization scripts** (`rootfs/etc/cont-init.d/`):
- `10-restore-state` - Restores state from DO Spaces backup
- `20-generate-config` - Builds moltbot.json from environment variables

**Services** (`rootfs/etc/services.d/`):
- `tailscale/` - Tailscale daemon (required)
- `moltbot/` - Moltbot gateway with Litestream
- `sshd/` - SSH server (if ENABLE_SSH=true)
- `backup/` - Periodic state backup (if persistence configured)

Users can add custom init scripts (prefix with `30-` or higher) and custom services.

## Networking

Tailscale is required for networking. The gateway binds to loopback and uses Tailscale serve mode for access via your tailnet.

Required environment variables:
- `TS_AUTHKEY` - Tailscale auth key

## Configuration

All gateway settings are driven by the config file (`moltbot.json`). The init script dynamically builds the config based on environment variables:

- Tailscale serve mode for networking
- Gradient AI provider (if `GRADIENT_API_KEY` set)

## Gradient AI Integration

Set `GRADIENT_API_KEY` to enable DigitalOcean's serverless AI inference with models:
- Llama 3.3 70B Instruct
- Claude 4.5 Sonnet / Opus 4.5
- DeepSeek R1 Distill Llama 70B

## Persistence

Optional DO Spaces backup via Litestream + s3cmd:
- SQLite: real-time replication via Litestream
- JSON state: periodic backup every 5 minutes
- Tailscale state: periodic backup every 5 minutes
