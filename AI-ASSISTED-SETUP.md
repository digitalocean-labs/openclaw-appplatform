# AI-Assisted Moltbot Setup

This guide enables AI coding assistants (Claude Code, Cursor, Codex, Gemini, etc.) to deploy and configure Moltbot on DigitalOcean App Platform.

## Overview

- Uses [do-app-sandbox](https://pypi.org/project/do-app-sandbox/) SDK for remote execution on app container console
- References [do-app-platform-skills](https://github.com/digitalocean-labs/do-app-platform-skills) for best practices
- Follows progressive deployment stages (CLI → UI+ngrok → Tailscale)

## Prerequisites

Before asking your AI assistant to deploy Moltbot:

```bash
# 1. Install and configure doctl
brew install doctl
doctl auth init

# 2. Install do-app-sandbox
pip install do-app-sandbox
# or with uv:
uv pip install do-app-sandbox

# 3. Clone app-platform-skills (if not available)
git clone https://github.com/digitalocean-labs/do-app-platform-skills ~/.claude/skills/do-app-platform-skills
```

---

## Stage 1: Deploy CLI-Only ($5/mo)

The simplest deployment - gateway with CLI access only via `doctl apps console`.

### Prompt

```
Deploy Moltbot to DigitalOcean App Platform using the CLI-only configuration.

Use the app spec from https://github.com/digitalocean-labs/moltbot-appplatform with:
- Instance size: basic-xxs (1 CPU, 512MB shared)
- All feature flags disabled (ENABLE_NGROK=false, ENABLE_TAILSCALE=false, ENABLE_SPACES=false)
- ENABLE_UI=true (so we can use UI later if needed)

After deployment:
1. Use do-app-sandbox to connect to the container
2. Run: mb gateway health --url ws://127.0.0.1:18789
3. Run: mb channels status --probe
4. Show me the gateway token from: cat /run/s6/container_environment/MOLTBOT_GATEWAY_TOKEN

Reference the do-app-platform-skills for deployment best practices.
```

### Verification

```bash
# Connect to console
doctl apps console <app-id> moltbot

# In console, verify:
mb gateway health --url ws://127.0.0.1:18789
mb channels status --probe
```

---

## Stage 2: Add Web UI + ngrok ($12/mo)

Public URL access to the Control UI via ngrok tunnel.

### Prompt

```
Upgrade my Moltbot deployment to Stage 2 with ngrok for public access.

Update the app configuration:
- Instance size: basic-xs (1 CPU, 1GB shared)
- Set ENABLE_NGROK=true
- Add NGROK_AUTHTOKEN (I'll provide it: <your-token>)

After deployment:
1. Connect via do-app-sandbox
2. Get the ngrok URL: curl -s http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url'
3. Verify gateway is accessible
4. Show me how to access the Control UI

Use do-app-platform-skills for the update process.
```

### Getting ngrok Token

1. Sign up at https://dashboard.ngrok.com
2. Go to: Your Authtoken → Copy

### Verification

```bash
# Get ngrok URL
curl -s http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url'

# Access in browser: <ngrok-url>
# Login with your gateway token
```

---

## Stage 3: Production with Tailscale ($25/mo)

Private network access - most secure for production use.

### Prompt

```
Upgrade my Moltbot deployment to Stage 3 with Tailscale for private access.

Update the app configuration:
- Instance size: basic-s (1 CPU, 2GB shared)
- Set ENABLE_NGROK=false
- Set ENABLE_TAILSCALE=true
- Add TS_AUTHKEY (I'll provide it)
- Set STABLE_HOSTNAME=moltbot

After deployment:
1. Verify Tailscale is connected
2. Show me the Tailscale hostname
3. Verify I can access via https://moltbot.<my-tailnet>.ts.net

Reference do-app-platform-skills for Tailscale integration.
```

### Getting Tailscale Auth Key

1. Go to https://login.tailscale.com/admin/settings/keys
2. Generate new auth key (reusable recommended for App Platform)

### Verification

```bash
# In console
tailscale status

# Access via browser
https://moltbot.<your-tailnet>.ts.net
```

---

## Adding Persistence (Any Stage)

Add DO Spaces backup to preserve data across restarts.

### Prompt

```
Add persistence to my Moltbot deployment using DO Spaces.

I have a Spaces bucket ready:
- Bucket: <bucket-name>
- Endpoint: <region>.digitaloceanspaces.com
- Access Key: <key>
- Secret Key: <secret>

Update the configuration:
- Set ENABLE_SPACES=true
- Add all the Spaces environment variables
- Add RESTIC_PASSWORD for backup encryption

After deployment:
1. Verify backup service is running
2. Confirm data will persist across restarts

Use do-app-platform-skills for Spaces configuration.
```

---

## Channel Setup: WhatsApp

Setting up WhatsApp requires scanning a QR code, which is challenging for AI assistants.

### The Challenge

- The `mb channels login` command displays a QR code and waits for scanning
- This blocks the terminal, preventing the AI from getting a prompt back
- The QR code needs to be visible for the user to scan

### AI Solution: pexpect + File Streaming

The AI assistant can use this approach:

1. Use `pexpect` to spawn the doctl console session
2. Stream all output to a local file
3. Ask the user to open the file and scan the QR code
4. Monitor for "linked" confirmation
5. Restart the service and verify

### Prompt for WhatsApp Setup

```
Help me connect WhatsApp to my Moltbot deployment.

Use the do-app-sandbox SDK with pexpect to:
1. Connect to my Moltbot container (app-id: <app-id>)
2. First logout any existing session: mb channels logout --channel whatsapp
3. Restart moltbot: /command/s6-svc -r /run/service/moltbot
4. Run the login command and stream output to a local file so I can see the QR code
5. Tell me to open the file and scan the QR code with my WhatsApp
6. Wait for "linked" confirmation
7. Restart moltbot service
8. Verify connection: mb channels status --probe
9. Send me a test message to verify everything works

My phone number is: <your-phone>

Reference the CHEATSHEET.md for the correct commands.
```

### Example Implementation (for AI reference)

```python
import pexpect
import time

OUTPUT_FILE = "/path/to/qr-output.txt"

# Spawn console session
child = pexpect.spawn(
    'doctl', ['apps', 'console', '<app-id>', 'moltbot'],
    encoding='utf-8',
    timeout=180
)

# Log output to file
logfile = open(OUTPUT_FILE, 'w')
child.logfile_read = logfile

# Wait for prompt
child.expect(r'[@#\$] ', timeout=30)

# Run login command
child.sendline('mb channels login --channel whatsapp')

print(f"QR code being written to: {OUTPUT_FILE}")
print("Open this file to scan the QR code!")

# Wait for linked confirmation
child.expect(['linked', 'Linked'], timeout=180)
print("WhatsApp linked successfully!")

logfile.close()
child.close()
```

### Verification Steps

```bash
# Check channel status
mb channels status --probe
# Should show: WhatsApp default: enabled, configured, linked, running, connected

# Send test message
mb message send --channel whatsapp --target "+1234567890" --message "Hello from Moltbot!"

# Check for reply in logs
tail -f /data/.moltbot/logs/gateway.log
```

---

## Deployment Modes

| Mode | When to Use |
|------|-------------|
| **Laptop (doctl)** | Development, testing, quick iterations |
| **GitHub Actions** | Production, CI/CD, team deployments |

### Deploy from Laptop

```bash
# Validate spec
doctl apps spec validate app.yaml

# Create app
doctl apps create --spec app.yaml

# Or update existing
doctl apps update <app-id> --spec app.yaml
```

### Deploy from GitHub Actions

See `.github/workflows/deploy.yml` for automated deployment on push.

---

## Reference

### Key Files

| File | Purpose |
|------|---------|
| `app.yaml` | App Platform spec with feature flags |
| `.do/deploy.template.yaml` | Template for Deploy to DO button |
| `CHEATSHEET.md` | CLI commands reference |
| `.env.example` | Environment variable template |

### Important Commands

```bash
# Always use mb wrapper in console
mb <command>

# Service management
/command/s6-svc -r /run/service/moltbot    # Restart
/command/s6-svc -d /run/service/moltbot    # Stop
/command/s6-svc -u /run/service/moltbot    # Start

# View config
cat /data/.moltbot/moltbot.json | jq .

# View token
cat /run/s6/container_environment/MOLTBOT_GATEWAY_TOKEN
```

### Troubleshooting

| Issue | Solution |
|-------|----------|
| "Command not found" in console | Use `mb` wrapper instead of `moltbot` |
| Gateway not starting | Check logs: `tail -100 /data/.moltbot/logs/gateway.log` |
| WhatsApp disconnected | Re-run `mb channels login` and scan QR |
| ngrok URL not working | Restart ngrok: `/command/s6-svc -r /run/service/ngrok` |

### External Resources

- [Moltbot Documentation](https://docs.molt.bot)
- [do-app-sandbox PyPI](https://pypi.org/project/do-app-sandbox/)
- [do-app-platform-skills](https://github.com/digitalocean-labs/do-app-platform-skills)
- [DigitalOcean App Platform Docs](https://docs.digitalocean.com/products/app-platform/)
