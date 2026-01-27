# Clawdbot App Platform Image

Pre-built Docker image for deploying [Clawdbot](https://github.com/clawdbot/clawdbot) on DigitalOcean App Platform.

[![Deploy to DO](https://www.deploytodo.com/do-btn-blue.svg)](https://cloud.digitalocean.com/apps/new?repo=https://github.com/digitalocean-labs/clawdbot-appplatform/tree/main)

## Features

- **Fast boot** (~30 seconds vs 5-10 min source build)
- **Auto-update** on every container start
- **Optional persistence** via Litestream + DO Spaces
- **Multi-arch** support (amd64/arm64)

## Quick Start

1. Click the **Deploy to DO** button above
2. Set `SETUP_PASSWORD` when prompted
3. Wait for deployment (~1 minute)
4. Open `https://<your-app>.ondigitalocean.app/setup` to complete setup

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│           GHCR Image: ghcr.io/bikramkgupta/                 │
│                    clawdbot-appplatform                          │
│  ┌───────────┐  ┌───────────┐  ┌────────────────────────────┐   │
│  │ Node 24   │  │ Clawdbot  │  │ Litestream (optional)      │   │
│  │ (slim)    │  │ (latest)  │  │ SQLite → DO Spaces backup  │   │
│  └───────────┘  └───────────┘  └────────────────────────────┘   │
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

1. Create a Spaces bucket in the same region as your app
2. Create Spaces access keys (Settings → API → Spaces Keys)
3. Add the Litestream environment variables to your app
4. Redeploy

The app will automatically restore from backup on boot and continuously replicate changes.

## Documentation

- [Full deployment guide](https://docs.clawd.bot/digitalocean)
- [Clawdbot documentation](https://docs.clawd.bot)

## License

MIT
