# Clawdbot App Platform Image

Pre-built Docker image for deploying [Clawdbot](https://github.com/clawdbot/clawdbot) on DigitalOcean App Platform.

[![Deploy to DO](https://www.deploytodo.com/do-btn-blue.svg)](https://cloud.digitalocean.com/apps/new?repo=https://github.com/digitalocean-labs/clawdbot-appplatform/tree/main)

## Features

- **Fast boot** (~30 seconds vs 5-10 min source build)
- **Flexible networking** - Tailscale (private) or LAN (public) modes
- **Optional persistence** via Litestream + DO Spaces
- **Gradient AI support** - Use DigitalOcean's serverless AI inference
- **Multi-arch** support (amd64/arm64)

## Quick Start

1. Click the **Deploy to DO** button above
2. Set `SETUP_PASSWORD` when prompted
3. Wait for deployment (~1 minute)
4. Open `https://<your-app>.ondigitalocean.app/setup` to complete setup

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│           GHCR Image: ghcr.io/bikramkgupta/                      │
│                    clawdbot-appplatform                          │
│  ┌───────────┐  ┌───────────┐  ┌────────────────────────────┐   │
│  │ Node 24   │  │ Clawdbot  │  │ Litestream (optional)      │   │
│  │ (slim)    │  │ (latest)  │  │ SQLite → DO Spaces backup  │   │
│  └───────────┘  └───────────┘  └────────────────────────────┘   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Tailscale (optional) - Private networking via tailnet    │  │
│  └───────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

## Environment Variables

### Required

| Variable | Description |
|----------|-------------|
| `SETUP_PASSWORD` | Password for the web setup wizard |

### Recommended

| Variable | Description |
|----------|-------------|
| `CLAWDBOT_GATEWAY_TOKEN` | Admin token for gateway API access |

### Gateway Mode

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAWDBOT_GATEWAY_MODE` | `tailscale` or `lan` | `tailscale` |
| `PORT` | HTTP port (LAN mode only) | `8080` |

**Tailscale mode** (default): Access via your private tailnet. Requires:
- `TS_AUTHKEY` - Tailscale auth key
- Deploy as a **worker** (not service)

**LAN mode**: Public HTTP access behind Cloudflare/App Platform proxy. Requires:
- `SETUP_PASSWORD` for password auth, or uses token auth

### Optional (Gradient AI)

| Variable | Description |
|----------|-------------|
| `GRADIENT_API_KEY` | DigitalOcean Gradient AI Model Access Key |

When set, adds Gradient as a model provider with access to:
- Llama 3.3 70B Instruct
- Claude 4.5 Sonnet
- Claude Opus 4.5
- DeepSeek R1 Distill Llama 70B

### Optional (Tailscale)

| Variable | Description |
|----------|-------------|
| `TS_AUTHKEY` | Tailscale auth key for joining your tailnet |
| `TS_HOSTNAME` | Hostname on your tailnet |

### Optional (Persistence)

Without these, the app runs in ephemeral mode - state is lost on redeploy.

| Variable | Description | Example |
|----------|-------------|---------|
| `LITESTREAM_ACCESS_KEY_ID` | DO Spaces access key | |
| `LITESTREAM_SECRET_ACCESS_KEY` | DO Spaces secret key | |
| `SPACES_ENDPOINT` | Spaces endpoint | `tor1.digitaloceanspaces.com` |
| `SPACES_BUCKET` | Spaces bucket name | `my-clawdbot-backup` |

## Resource Requirements

| Resource | Value |
|----------|-------|
| CPU | 1 shared vCPU |
| RAM | 2 GB |
| Instance | `apps-s-1vcpu-2gb` |
| Cost | ~$25/mo (+ $5/mo Spaces optional) |

> **Note:** The gateway requires 2GB RAM to start reliably. Using `basic-xs` (1GB) will result in OOM errors.

## Available Regions

- `nyc` - New York
- `ams` - Amsterdam
- `sfo` - San Francisco
- `sgp` - Singapore
- `lon` - London
- `fra` - Frankfurt
- `blr` - Bangalore
- `syd` - Sydney
- `tor` - Toronto (default)

Edit the `region` field in `app.yaml` to change.

## Manual Deployment

```bash
# Clone and deploy
git clone https://github.com/digitalocean-labs/clawdbot-appplatform
cd clawdbot-appplatform

# Validate spec
doctl apps spec validate app.yaml

# Create app
doctl apps create --spec app.yaml

# Set secrets in the DO dashboard
```

## Setting Up Persistence

App Platform doesn't have persistent volumes, so this image uses DO Spaces for state backup.

### What Gets Persisted

| Data Type | Backup Method | Description |
|-----------|--------------|-------------|
| Memory search index | Litestream (real-time) | SQLite database for vector search |
| Config, devices, sessions | S3 backup (every 5 min) | JSON state files |

### Setup Steps

1. **Create a Spaces bucket** in the same region as your app
   - Go to **Spaces Object Storage** → **Create Bucket**
   - Name: e.g., `clawdbot-backup`
   - Region: match your app (e.g., `tor1` for Toronto)

2. **Create Spaces access keys**
   - Go to **Settings → API → Spaces Keys**
   - Click **Generate New Key**
   - Save both Access Key and Secret Key

3. **Add environment variables** to your App Platform app:
   - `LITESTREAM_ACCESS_KEY_ID` = your access key
   - `LITESTREAM_SECRET_ACCESS_KEY` = your secret key
   - `SPACES_ENDPOINT` = `<region>.digitaloceanspaces.com` (e.g., `tor1.digitaloceanspaces.com`)
   - `SPACES_BUCKET` = your bucket name

4. **Redeploy** the app

### How It Works

On startup:
1. Restores JSON state backup from Spaces (if exists)
2. Restores SQLite memory database via Litestream (if exists)
3. Starts the gateway

During operation:
- Litestream continuously replicates SQLite changes (1s sync interval)
- JSON state is backed up every 5 minutes
- On graceful shutdown (SIGTERM), final state backup is saved

## Tailscale Setup

For private access via Tailscale instead of public HTTP:

1. Set `CLAWDBOT_GATEWAY_MODE=tailscale`
2. Create a Tailscale auth key at https://login.tailscale.com/admin/settings/keys
3. Set `TS_AUTHKEY` to your auth key
4. Deploy as a **worker** (use `.do/deploy.template.yaml`)
5. Access via `https://clawdbot.<your-tailnet>.ts.net`

## Documentation

- [Full deployment guide](https://docs.clawd.bot/digitalocean)
- [Clawdbot documentation](https://docs.clawd.bot)

## License

MIT
