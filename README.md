# Moltbot on DigitalOcean App Platform

Deploy [Moltbot](https://github.com/moltbot/moltbot) - a multi-channel AI messaging gateway - on DigitalOcean App Platform in minutes.

[![Deploy to DO](https://www.deploytodo.com/do-btn-blue.svg)](https://cloud.digitalocean.com/apps/new?repo=https://github.com/digitalocean-labs/clawdbot-appplatform/tree/main)

## Quick Start: Choose Your Stage

| Stage | What You Get | Cost | Access Method |
|-------|--------------|------|---------------|
| **1. CLI Only** | Gateway + CLI | ~$10/mo | `doctl apps console` |
| **2. + Web UI + ngrok** | Control UI + Public URL | ~$10/mo | ngrok URL |
| **3. + Tailscale** | Private Network | ~$25/mo | Tailscale hostname |
| **+ Persistence** | Data survives restarts | existing subscription | DO Spaces |

**Start simple, add features as needed.** Most users start with Stage 2 (ngrok) for the easiest setup.

---

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                      moltbot-appplatform                           │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ s6-overlay - Process supervision and init system             │  │
│  └──────────────────────────────────────────────────────────────┘  │
│  ┌─────────────┐  ┌───────────────────┐  ┌────────────────────┐   │
│  │ Ubuntu      │  │ Moltbot Gateway   │  │ Litestream         │   │
│  │ Noble+Node  │  │ WebSocket :18789  │  │ (ENABLE_SPACES)    │   │
│  │ + nvm       │  │ + Control UI      │  │ SQLite → DO Spaces │   │
│  └─────────────┘  └───────────────────┘  └────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Access Layer (choose one):                                   │  │
│  │  • Console only (default) - doctl apps console               │  │
│  │  • ngrok (ENABLE_NGROK) - Public tunnel to UI                │  │
│  │  • Tailscale (ENABLE_TAILSCALE) - Private network            │  │
│  └──────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Optional: SSH Server (ENABLE_SSH=true)                       │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
   ┌──────────┐        ┌──────────┐        ┌──────────┐
   │ WhatsApp │        │ Telegram │        │ Discord  │
   │ Signal   │        │ Slack    │        │ MS Teams │
   │ iMessage │        │ Matrix   │        │ + more   │
   └──────────┘        └──────────┘        └──────────┘
```

---

## Stage 1: CLI Only - The Basics

The simplest deployment. Access via `doctl apps console` and use CLI commands.

### Deploy

```bash
# Clone the repo
git clone https://github.com/digitalocean-labs/moltbot-appplatform
cd moltbot-appplatform

# Edit app.yaml - set instance size for Stage 1
# instance_size_slug: apps-s-1vcpu-1gb-fixed  # 1 CPU, 1GB (minimum for stable operation)

# Set your SETUP_PASSWORD in app.yaml or DO dashboard

# Deploy
doctl apps create --spec app.yaml
```

### Connect

```bash
# Get app ID
doctl apps list

# Open console
doctl apps console <app-id> moltbot

# Verify gateway is running
mb gateway health --url ws://127.0.0.1:18789

# Check channel status
mb channels status --probe
```

### What's Included

- ✅ Moltbot gateway (WebSocket on port 18789)
- ✅ CLI access via `mb` command
- ✅ All channel plugins (WhatsApp, Telegram, Discord, etc.)
- ❌ No web UI access (use CLI/TUI)
- ❌ No public URL
- ❌ Data lost on restart

---

## Stage 2: Add Web UI + ngrok

Add a public URL to access the Control UI. **Recommended for getting started.**

### Get ngrok Token

1. Sign up at https://dashboard.ngrok.com
2. Copy your authtoken from the dashboard

### Deploy

Update `app.yaml`:

```yaml
instance_size_slug: apps-s-1vcpu-1gb-fixed  # 1 CPU, 1GB

envs:
  - key: ENABLE_NGROK
    value: "true"
  - key: NGROK_AUTHTOKEN
    type: SECRET
    # Set value in DO dashboard
```

### Get Your URL

```bash
# In console
curl -s http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url'
```

Or check the ngrok dashboard at https://dashboard.ngrok.com/tunnels

### What's Added

- ✅ Everything from Stage 1
- ✅ Web Control UI
- ✅ Public URL via ngrok
- ❌ URL changes on restart (use Tailscale for stable URL)
- ❌ Data lost on restart

---

## Stage 3: Production with Tailscale

Private network access via your Tailscale tailnet. **Recommended for production.**

### Get Tailscale Auth Key

1. Go to https://login.tailscale.com/admin/settings/keys
2. Generate a reusable auth key

### Deploy

Update `app.yaml`:

```yaml
instance_size_slug: apps-s-1vcpu-2gb  # 1 CPU, 2GB

envs:
  - key: ENABLE_NGROK
    value: "false"
  - key: ENABLE_TAILSCALE
    value: "true"
  - key: TS_AUTHKEY
    type: SECRET
  - key: TS_HOSTNAME
    value: moltbot
```

### Access

```
https://moltbot.<your-tailnet>.ts.net
```

### What's Added

- ✅ Everything from Stage 1 & 2
- ✅ Stable hostname on your tailnet
- ✅ Private access (only your devices)
- ✅ Production-grade security
- ❌ Data lost on restart (add Spaces for persistence)

---

## Adding Persistence (Any Stage)

Without persistence, all data is lost when the container restarts. Add DO Spaces to preserve:

- Channel sessions (WhatsApp linking, etc.)
- Configuration changes
- Memory/search index
- Tailscale state

### Setup DO Spaces

1. **Create a Spaces bucket** in the same region as your app
   - Go to **Spaces Object Storage** → **Create Bucket**

2. **Create access keys**
   - Go to **API** → **Spaces Keys** → **Generate New Key**

3. **Update app.yaml**:

```yaml
envs:
  - key: ENABLE_SPACES
    value: "true"
  - key: LITESTREAM_ACCESS_KEY_ID
    type: SECRET
  - key: LITESTREAM_SECRET_ACCESS_KEY
    type: SECRET
  - key: SPACES_ENDPOINT
    value: tor1.digitaloceanspaces.com  # Match your region
  - key: SPACES_BUCKET
    value: moltbot-backup
  - key: RESTIC_PASSWORD
    type: SECRET
```

### What Gets Persisted

| Data | Method | Frequency |
|------|--------|-----------|
| SQLite (search index) | Litestream | Real-time |
| Config, sessions | Restic | Every 5 min |
| Tailscale state | Restic | Every 5 min |

---

## AI-Assisted Setup

Want an AI assistant to help deploy and configure Moltbot? See **[AI-ASSISTED-SETUP.md](AI-ASSISTED-SETUP.md)** for:

- Copy-paste prompts for each stage
- WhatsApp channel setup (with QR code handling)
- Verification steps
- Works with Claude Code, Cursor, Codex, Gemini, etc.

---

## CLI Cheat Sheet

The `mb` command is a wrapper that runs moltbot with the correct user and environment. **Always use `mb` in console sessions.**

```bash
# Gateway
mb gateway health --url ws://127.0.0.1:18789
mb gateway status

# Channels
mb channels status --probe
mb channels login                    # WhatsApp QR code

# Messages
mb message send --channel whatsapp --target "+1234567890" --message "Hello!"

# Services
/command/s6-svc -r /run/service/moltbot    # Restart
/command/s6-svc -r /run/service/ngrok      # Restart ngrok

# Logs
tail -f /data/.moltbot/logs/gateway.log

# Config
cat /data/.moltbot/moltbot.json | jq .
```

See **[CHEATSHEET.md](CHEATSHEET.md)** for the complete reference.

---

## Environment Variables

### Required

| Variable | Description |
|----------|-------------|
| `SETUP_PASSWORD` | Password for web setup wizard |

### Feature Flags

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_NGROK` | `false` | Enable ngrok tunnel |
| `ENABLE_TAILSCALE` | `false` | Enable Tailscale |
| `ENABLE_SPACES` | `false` | Enable DO Spaces persistence |
| `ENABLE_UI` | `true` | Enable web Control UI |
| `ENABLE_SSH` | `false` | Enable SSH server |

### ngrok (when ENABLE_NGROK=true)

| Variable | Description |
|----------|-------------|
| `NGROK_AUTHTOKEN` | Your ngrok auth token |

### Tailscale (when ENABLE_TAILSCALE=true)

| Variable | Description |
|----------|-------------|
| `TS_AUTHKEY` | Tailscale auth key |
| `TS_HOSTNAME` | Hostname on your tailnet |

### Spaces (when ENABLE_SPACES=true)

| Variable | Description |
|----------|-------------|
| `LITESTREAM_ACCESS_KEY_ID` | Spaces access key |
| `LITESTREAM_SECRET_ACCESS_KEY` | Spaces secret key |
| `SPACES_ENDPOINT` | e.g., `tor1.digitaloceanspaces.com` |
| `SPACES_BUCKET` | Your bucket name |
| `RESTIC_PASSWORD` | Backup encryption password |

### Optional

| Variable | Description |
|----------|-------------|
| `MOLTBOT_GATEWAY_TOKEN` | Gateway auth token (auto-generated if not set) |
| `GRADIENT_API_KEY` | DigitalOcean Gradient AI key |
| `GITHUB_USERNAME` | For SSH key fetching |

---

## Customization (s6-overlay)

The container uses [s6-overlay](https://github.com/just-containers/s6-overlay) for process supervision.

### Add Custom Init Scripts

Create `rootfs/etc/cont-init.d/30-my-script`:

```bash
#!/command/with-contenv bash
echo "Running my custom setup..."
```

### Add Custom Services

Create `rootfs/etc/services.d/my-daemon/run`:

```bash
#!/command/with-contenv bash
exec my-daemon --foreground
```

### Built-in Services

| Service | Description |
|---------|-------------|
| `moltbot` | Moltbot gateway |
| `ngrok` | ngrok tunnel (if enabled) |
| `tailscale` | Tailscale daemon (if enabled) |
| `litestream` | SQLite replication (if enabled) |
| `backup` | Restic backup (if enabled) |
| `sshd` | SSH server (if enabled) |

---

## Available Regions

| Code | Location |
|------|----------|
| `nyc` | New York |
| `ams` | Amsterdam |
| `sfo` | San Francisco |
| `sgp` | Singapore |
| `lon` | London |
| `fra` | Frankfurt |
| `blr` | Bangalore |
| `syd` | Sydney |
| `tor` | Toronto (default) |

---

## Documentation

- [Moltbot Documentation](https://docs.molt.bot)
- [DigitalOcean App Platform](https://docs.digitalocean.com/products/app-platform/)
- [AI-Assisted Setup Guide](AI-ASSISTED-SETUP.md)
- [CLI Cheat Sheet](CHEATSHEET.md)

---

## License

MIT
