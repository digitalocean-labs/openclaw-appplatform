# OpenClaw on DigitalOcean App Platform

Deploy [OpenClaw](https://github.com/openclaw/openclaw) - a multi-channel AI messaging gateway - on DigitalOcean App Platform in minutes.

[![Deploy to DO](https://www.deploytodo.com/do-btn-blue.svg)](https://cloud.digitalocean.com/apps/new?repo=https://github.com/digitalocean-labs/openclaw-appplatform/tree/main)

## Quick Start: Choose Your Stage

| Stage                   | What You Get            | Access Method        |
| ----------------------- | ----------------------- | -------------------- |
| **1. CLI Only**         | Gateway + CLI           | `doctl apps console` |
| **2. + Web UI + ngrok** | Control UI + Public URL | ngrok URL            |
| **3. + Tailscale**      | Private Network         | Tailscale hostname   |
| **+ Persistence**       | Data survives restarts  | DO Spaces            |

**Start simple, add features as needed.** Most users start with Stage 2 (ngrok) for the easiest setup.

---

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                      openclaw-appplatform                           │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ s6-overlay - Process supervision and init system             │  │
│  └──────────────────────────────────────────────────────────────┘  │
│  ┌─────────────┐  ┌───────────────────┐                            │
│  │ Ubuntu      │  │ OpenClaw Gateway  │                            │
│  │ Noble+Node  │  │ WebSocket :18789  │                            │
│  │ + nvm       │  │ + Control UI      │                            │
│  └─────────────┘  └───────────────────┘                            │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Access Layer (choose one):                                   │  │
│  │  • Console only (default) - doctl apps console               │  │
│  │  • ngrok (ENABLE_NGROK) - Public tunnel to UI                │  │
│  │  • Tailscale (TAILSCALE_ENABLE) - Private network            │  │
│  └──────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Optional: SSH Server (SSH_ENABLE=true)                        │  │
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
git clone https://github.com/digitalocean-labs/openclaw-appplatform
cd openclaw-appplatform

# Edit app.yaml - set instance size for Stage 1
# instance_size_slug: apps-s-1vcpu-2gb  # 1 CPU, 2GB (minimum for stable operation)

# Set your OPENCLAW_GATEWAY_TOKEN in app.yaml or DO dashboard

# Deploy
doctl apps create --spec app.yaml
```

### Connect

```bash
# Get app ID
doctl apps list

# Open console
doctl apps console <app-id> openclaw

# Verify gateway is running
openclaw gateway health --url ws://127.0.0.1:18789

# Check channel status
openclaw channels status --probe
```

### What's Included

- ✅ OpenClaw gateway (WebSocket on port 18789)
- ✅ CLI access via `openclaw` command
- ✅ All channel plugins (WhatsApp, Telegram, Discord, etc.)
- ❌ No web UI access (use CLI/TUI)
- ❌ No public URL
- ❌ Data lost on restart

---

## Stage 2: Add Web UI + ngrok

Add a public URL to access the Control UI. **Recommended for getting started.**

### Get ngrok Token

1. Sign up at <https://dashboard.ngrok.com>
2. Copy your authtoken from the dashboard

### Deploy

Update `app.yaml`:

```yaml
instance_size_slug: apps-s-1vcpu-2gb  # 1 CPU, 2GB

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

Or check the ngrok dashboard at <https://dashboard.ngrok.com/tunnels>

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

1. Go to <https://login.tailscale.com/admin/settings/keys>
2. Generate a reusable auth key

### Deploy

Update `app.yaml`:

```yaml
instance_size_slug: apps-s-1vcpu-2gb  # 1 CPU, 2GB

envs:
  - key: ENABLE_NGROK
    value: "false"
  - key: TAILSCALE_ENABLE
    value: "true"
  - key: TS_AUTHKEY
    type: SECRET
  - key: STABLE_HOSTNAME
    value: openclaw
```

### Access

```
https://openclaw.<your-tailnet>.ts.net
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
  - key: RESTIC_SPACES_ACCESS_KEY_ID
    type: SECRET
  - key: RESTIC_SPACES_SECRET_ACCESS_KEY
    type: SECRET
  - key: RESTIC_SPACES_ENDPOINT
    value: tor1.digitaloceanspaces.com  # Match your region
  - key: RESTIC_SPACES_BUCKET
    value: openclaw-backup
  - key: RESTIC_PASSWORD
    type: SECRET
```

### What Gets Persisted

The backup system uses [Restic](https://restic.net/) for incremental, encrypted snapshots to DigitalOcean Spaces.

| Path              | Contents                                         | Backup Frequency         |
| ----------------- | ------------------------------------------------ | ------------------------ |
| `/data/.openclaw` | Gateway config, channel sessions, agents, memory | Every 30s (configurable) |
| `/data/tailscale` | Tailscale connection state (persistent device)   | Every 30s                |
| `/etc`            | System configuration                             | Every 30s                |
| `/home`           | User files, Homebrew packages                    | Every 30s                |
| `/root`           | Root user data                                   | Every 30s                |

**Automatic Restore:**
- On container restart, `10-restore-state` init script automatically restores the latest snapshot for each path
- Restores are fast and incremental
- Data survives deployments, restarts, and instance replacements

**Repository Management:**
- Old snapshots are automatically pruned every hour
- Repository is encrypted with `RESTIC_PASSWORD`
- Stored in: `s3:<endpoint>/<bucket>/<hostname>/restic`

**Configuration File:**
Backup behavior is controlled by `/etc/digitalocean/backup.yaml`:
- **Backup paths**: What directories to back up
- **Exclusions**: Files to skip (*.lock, *.pid, *.sock)
- **Intervals**: Backup frequency (default: 30s), prune frequency (default: 1h)
- **Retention policy**: How many snapshots to keep (last 10, hourly 48, daily 30, etc.)

To customize, create `rootfs/etc/digitalocean/backup.yaml` in your repo and rebuild.

---

## AI-Assisted Setup

Want an AI assistant to help deploy and configure OpenClaw? See **[AI-ASSISTED-SETUP.md](AI-ASSISTED-SETUP.md)** for:

- Copy-paste prompts for each stage
- WhatsApp channel setup (with QR code handling)
- Verification steps
- Works with Claude Code, Cursor, Codex, Gemini, etc.

---

## CLI Cheat Sheet

The `openclaw` command is a wrapper that runs openclaw with the correct user and environment. **Always use `openclaw` in console sessions.**

```bash
# Gateway
openclaw gateway health --url ws://127.0.0.1:18789
openclaw gateway status

# Channels
openclaw channels status --probe
openclaw channels login                    # WhatsApp QR code

# Messages
openclaw message send --channel whatsapp --target "+1234567890" --message "Hello!"

# Services
/command/s6-svc -r /run/service/openclaw    # Restart
/command/s6-svc -r /run/service/ngrok      # Restart ngrok

# Logs
tail -f /data/.openclaw/logs/gateway.log

# Config
cat /data/.openclaw/openclaw.json | jq .
```

See **[CHEATSHEET.md](CHEATSHEET.md)** for the complete reference.

---

## Environment Variables

### Required

| Variable                 | Description                         |
| ------------------------ | ----------------------------------- |
| `OPENCLAW_GATEWAY_TOKEN` | Password for web setup wizard       |
| `STABLE_HOSTNAME`        | A stable hostname for this instance |

### Feature Flags

| Variable           | Default | Description                  |
| ------------------ | ------- | ---------------------------- |
| `ENABLE_NGROK`     | `false` | Enable ngrok tunnel          |
| `ENABLE_TAILSCALE` | `false` | Enable Tailscale             |
| `ENABLE_SPACES`    | `false` | Enable DO Spaces persistence |
| `ENABLE_UI`        | `true`  | Enable web Control UI        |
| `SSH_ENABLE`       | `false` | Enable SSH server            |

### ngrok (when ENABLE_NGROK=true)

| Variable          | Description           |
| ----------------- | --------------------- |
| `NGROK_AUTHTOKEN` | Your ngrok auth token |

### Tailscale (when TAILSCALE_ENABLE=true)

| Variable     | Description        |
| ------------ | ------------------ |
| `TS_AUTHKEY` | Tailscale auth key |

### Spaces (when ENABLE_SPACES=true)

| Variable                          | Description                         |
| --------------------------------- | ----------------------------------- |
| `RESTIC_SPACES_ACCESS_KEY_ID`     | Spaces access key                   |
| `RESTIC_SPACES_SECRET_ACCESS_KEY` | Spaces secret key                   |
| `RESTIC_SPACES_ENDPOINT`          | e.g., `tor1.digitaloceanspaces.com` |
| `RESTIC_SPACES_BUCKET`            | Your bucket name                    |
| `RESTIC_PASSWORD`                 | Backup encryption password          |

### Optional

| Variable                 | Description                                    |
| ------------------------ | ---------------------------------------------- |
| `OPENCLAW_GATEWAY_TOKEN` | Gateway auth token (auto-generated if not set) |
| `GRADIENT_API_KEY`       | DigitalOcean Gradient AI key                   |
| `GITHUB_USERNAME`        | For SSH key fetching                           |

---

## Customization (s6-overlay)

The container uses [s6-overlay](https://github.com/just-containers/s6-overlay) for process supervision.

### Dynamic MOTD

On login, you'll see a colorful status display. Run `motd` anytime to refresh.

| Section | Info |
|---------|------|
| 🖥️ System | Hostname, uptime, load, memory, disk (color-coded) |
| 🔗 Tailscale | Status, IP, relay, serve URL (if enabled) |
| 🦞 OpenClaw | Health status, configured channels, agent count |
| 📚 Links | OpenClaw docs, App Platform docs, source repo |

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

| Service     | Description                                              |
| ----------- | -------------------------------------------------------- |
| `openclaw`  | OpenClaw gateway                                         |
| `ngrok`     | ngrok tunnel (if enabled)                                |
| `tailscale` | Tailscale daemon (if enabled)                            |
| `backup`    | Restic backup service - creates snapshots (if enabled)   |
| `prune`     | Restic prune service - cleans old snapshots (if enabled) |
| `crond`     | Cron daemon for scheduled tasks                          |
| `sshd`      | SSH server (if enabled)                                  |

---

## Available Regions

| Code  | Location          |
| ----- | ----------------- |
| `nyc` | New York          |
| `atl` | Atlanta           |
| `ams` | Amsterdam         |
| `sfo` | San Francisco     |
| `sgp` | Singapore         |
| `lon` | London            |
| `fra` | Frankfurt         |
| `blr` | Bangalore         |
| `syd` | Sydney            |
| `tor` | Toronto (default) |

---

## Documentation

- [OpenClaw Documentation](https://docs.openclaw.ai)
- [DigitalOcean App Platform](https://docs.digitalocean.com/products/app-platform/)
- [AI-Assisted Setup Guide](AI-ASSISTED-SETUP.md)
- [CLI Cheat Sheet](CHEATSHEET.md)

---

## License

MIT
