# Clawdbot App Platform Deployment

## Overview

This repository contains the Docker configuration and deployment templates for running [Clawdbot](https://github.com/clawdbot/clawdbot) on DigitalOcean App Platform with Tailscale integration.

## Key Files

- `Dockerfile` - Multi-stage build that installs Tailscale and clawdbot via pnpm
- `entrypoint.sh` - Startup script that configures Tailscale and launches clawdbot gateway
- `app.yaml` - App Platform service configuration
- `.do/deploy.template.yaml` - App Platform worker configuration with Tailscale
- `litestream.yml` - SQLite replication config for persistence via DO Spaces
- `tailscale` - Wrapper script to inject socket path for tailscale CLI

## Deployment

Deploy as a **worker** (not service) to support Tailscale networking. The app is accessed via your Tailscale network rather than a public URL.

## Environment Variables

Required:
- `TS_AUTHKEY` - Tailscale auth key for joining your tailnet
- `SETUP_PASSWORD` - Password for clawdbot Control UI

Optional (for persistence):
- `LITESTREAM_ACCESS_KEY_ID` / `LITESTREAM_SECRET_ACCESS_KEY` - DO Spaces credentials
- `SPACES_ENDPOINT` / `SPACES_BUCKET` - DO Spaces configuration
