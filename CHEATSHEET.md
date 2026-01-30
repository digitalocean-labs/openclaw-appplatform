# Moltbot CLI Cheat Sheet

## The `mb` Command

**IMPORTANT:** In console sessions, always use `mb` instead of `moltbot` directly.

The `mb` wrapper script runs moltbot commands as the correct user with proper environment. Without it, you'll get "command not found" errors when running as root.

```bash
# ✅ Correct - use mb
mb channels status --probe

# ❌ Wrong - moltbot not in root's PATH
moltbot channels status --probe
```

---

## Console Access

```bash
doctl apps list                              # List apps, get app ID
doctl apps console <app-id> moltbot          # Open console session
```

---

## Gateway Status

```bash
mb gateway health --url ws://127.0.0.1:18789      # Check gateway is running
mb gateway status                                  # Gateway info
```

---

## Configuration

```bash
cat /data/.moltbot/moltbot.json | jq .            # Pretty print full config
cat /data/.moltbot/moltbot.json | jq .gateway     # Gateway section
cat /data/.moltbot/moltbot.json | jq .plugins     # Plugins section
cat /data/.moltbot/moltbot.json | jq .models      # Models/providers
```

---

## Channel Status

```bash
mb channels status                                # Basic channel status
mb channels status --probe                        # Probe all channels (detailed)
```

---

## WhatsApp Setup

```bash
mb channels login                                 # Start QR code linking
                                                  # Scan with WhatsApp app:
                                                  # Settings > Linked Devices > Link

/command/s6-svc -r /run/service/moltbot           # Restart after linking
mb channels status --probe                        # Verify connected
```

---

## Send Messages

```bash
# WhatsApp
mb message send --channel whatsapp --target "+14085551234" --message "Hello!"

# With media
mb message send --channel whatsapp --target "+14085551234" \
  --message "Check this out" --media /path/to/image.png

# Telegram
mb message send --channel telegram --target @username --message "Hello!"
mb message send --channel telegram --target 123456789 --message "Hello!"

# Discord
mb message send --channel discord --target channel:123456 --message "Hello!"
```

---

## Service Management (s6-overlay)

```bash
/command/s6-svc -r /run/service/moltbot           # Restart moltbot
/command/s6-svc -r /run/service/ngrok             # Restart ngrok
/command/s6-svc -r /run/service/tailscale         # Restart tailscale
/command/s6-svc -d /run/service/moltbot           # Stop moltbot
/command/s6-svc -u /run/service/moltbot           # Start moltbot

ls /run/service/                                  # List all services
```

---

## Logs

```bash
tail -f /data/.moltbot/logs/gateway.log           # Gateway logs (live)
tail -100 /data/.moltbot/logs/gateway.log         # Last 100 lines
mb logs --follow                                  # Moltbot log command
```

---

## Environment & Tokens

```bash
cat /run/s6/container_environment/MOLTBOT_GATEWAY_TOKEN   # Current token
env | grep MOLTBOT                                # All moltbot env vars
env | grep ENABLE                                 # Feature flags
```

---

## ngrok (when ENABLE_NGROK=true)

```bash
curl -s http://127.0.0.1:4040/api/tunnels | jq .  # Get ngrok tunnel info
curl -s http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url'
```

---

## Quick Diagnostics

```bash
# Full system check
mb gateway health --url ws://127.0.0.1:18789 && \
mb channels status --probe && \
echo "--- Config ---" && \
cat /data/.moltbot/moltbot.json | jq .

# Check what's running
ps aux | grep -E "(moltbot|ngrok|tailscale)"

# Disk usage
df -h /data
```

---

## Pairing & Directory

```bash
mb pairing list                                   # View pending pairing requests
mb pairing approve <code>                         # Approve a pairing code
mb directory search --query "john"                # Search contacts
```

---

## Agents

```bash
mb agents list                                    # List configured agents
mb agents status                                  # Agent status
```

---

## Troubleshooting

```bash
# Restart moltbot
/command/s6-svc -r /run/service/moltbot

# Check if gateway port is listening
ss -tlnp | grep 18789

# Test gateway WebSocket
curl -I http://127.0.0.1:18789

# Re-run config generation
/etc/cont-init.d/20-generate-config

# Check service dependencies
ls /etc/services.d/*/dependencies.d/
```

---

## Common Issues & Fixes

| Issue | Fix |
|-------|-----|
| "Gateway token not configured" | `jq .gateway.auth.token /data/.moltbot/moltbot.json` |
| WhatsApp disconnected after restart | `mb channels login` (re-scan QR) |
| ngrok tunnel not accessible | `curl http://127.0.0.1:4040/api/tunnels` then restart |
| Command not found (as root) | Use `mb` wrapper instead of `moltbot` |
