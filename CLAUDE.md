# Clawdbot App Platform Deployment

## Overview

This repository contains the Docker configuration and deployment templates for running [Clawdbot](https://github.com/clawdbot/clawdbot) on DigitalOcean App Platform.

## Key Files

- `Dockerfile` - Builds image with Tailscale, Homebrew, pnpm, and clawdbot
- `entrypoint.sh` - Builds config from env vars and starts gateway
- `app.yaml` - App Platform service configuration (LAN mode)
- `.do/deploy.template.yaml` - App Platform worker configuration (Tailscale mode)
- `litestream.yml` - SQLite replication config for persistence via DO Spaces
- `tailscale` - Wrapper script to inject socket path for tailscale CLI

## Gateway Modes

The gateway mode is controlled by `CLAWDBOT_GATEWAY_MODE` env var:

### Tailscale Mode (default)
- `CLAWDBOT_GATEWAY_MODE=tailscale`
- Access via private tailnet
- Requires `TS_AUTHKEY`
- Deploy as worker (not service)
- Config: `bind: loopback`, `tailscale.mode: serve`

### LAN Mode
- `CLAWDBOT_GATEWAY_MODE=lan`
- Public HTTP access on `PORT` (default 8080)
- Behind Cloudflare proxy (trustedProxies enabled)
- Auth via password (`SETUP_PASSWORD`) or token

## Configuration

All gateway settings are driven by the config file (`clawdbot.json`), not CLI params. The entrypoint dynamically builds the config based on environment variables:

- Gateway mode and binding
- Auth mode (tailscale, password, or token)
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
