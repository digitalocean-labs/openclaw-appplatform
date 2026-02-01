# OpenClaw CLI Cheat Sheet

## The `openclaw` Command

**IMPORTANT:** In console sessions, always use the `openclaw` wrapper command.

The `openclaw` wrapper script (in `/usr/local/bin/`) runs commands as the correct user with proper environment. Without it, you'll get "command not found" errors when running as root.

```bash
# ✅ Correct - use the wrapper
openclaw channels status --probe

# ❌ Wrong - running the binary directly won't work as root
/home/openclaw/.local/bin/openclaw channels status --probe
```

---

## Console Access

```bash
doctl apps list                              # List apps, get app ID
doctl apps console <app-id> openclaw          # Open console session
motd                                         # Show system info (MOTD)
```

---

## Gateway Status

```bash
openclaw gateway health --url ws://127.0.0.1:18789      # Check gateway is running
openclaw gateway status                                  # Gateway info
```

---

## Configuration

```bash
cat /data/.openclaw/openclaw.json | jq .            # Pretty print full config
cat /data/.openclaw/openclaw.json | jq .gateway     # Gateway section
cat /data/.openclaw/openclaw.json | jq .plugins     # Plugins section
cat /data/.openclaw/openclaw.json | jq .models      # Models/providers
```

---

## Channel Status

```bash
openclaw channels status                                # Basic channel status
openclaw channels status --probe                        # Probe all channels (detailed)
```

---

## WhatsApp Setup

```bash
openclaw channels login                                 # Start QR code linking
                                                  # Scan with WhatsApp app:
                                                  # Settings > Linked Devices > Link

/command/s6-svc -r /run/service/openclaw           # Restart after linking
openclaw channels status --probe                        # Verify connected
```

---

## Send Messages

```bash
# WhatsApp
openclaw message send --channel whatsapp --target "+14085551234" --message "Hello!"

# With media
openclaw message send --channel whatsapp --target "+14085551234" \
  --message "Check this out" --media /path/to/image.png

# Telegram
openclaw message send --channel telegram --target @username --message "Hello!"
openclaw message send --channel telegram --target 123456789 --message "Hello!"

# Discord
openclaw message send --channel discord --target channel:123456 --message "Hello!"
```

---

## Service Management (s6-overlay)

```bash
/command/s6-svc -r /run/service/openclaw           # Restart openclaw
/command/s6-svc -r /run/service/ngrok             # Restart ngrok
/command/s6-svc -r /run/service/tailscale         # Restart tailscale
/command/s6-svc -d /run/service/openclaw           # Stop openclaw
/command/s6-svc -u /run/service/openclaw           # Start openclaw

ls /run/service/                                  # List all services
```

---

## Logs

```bash
tail -f /data/.openclaw/logs/gateway.log           # Gateway logs (live)
tail -100 /data/.openclaw/logs/gateway.log         # Last 100 lines
openclaw logs --follow                                  # OpenClaw log command
```

---

## Environment & Tokens

```bash
cat /run/s6/container_environment/OPENCLAW_GATEWAY_TOKEN   # Current token
env | grep OPENCLAW                                # All openclaw env vars
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
# Show system info (MOTD)
motd

# Full system check
openclaw gateway health --url ws://127.0.0.1:18789 && \
openclaw channels status --probe && \
echo "--- Config ---" && \
cat /data/.openclaw/openclaw.json | jq .

# Check what's running
ps aux | grep -E "(openclaw|ngrok|tailscale)"

# Disk usage
df -h /data
```

---

## Pairing & Directory

```bash
openclaw pairing list                                   # View pending pairing requests
openclaw pairing approve <code>                         # Approve a pairing code
openclaw directory search --query "john"                # Search contacts
```

---

## Agents

```bash
openclaw agents list                                    # List configured agents
openclaw agents status                                  # Agent status
```

---

## Backup & Restore (Restic)

```bash
# View snapshots
restic snapshots

# View latest snapshot for a specific path
restic snapshots --path /data/.openclaw --latest 1

# Manually trigger backup
/usr/local/bin/restic-backup

# Manually restore a path
restic restore latest --target / --include /data/.openclaw

# Check repository status
restic check

# View repository stats
restic stats

# Prune old snapshots (done automatically hourly)
/usr/local/bin/restic-prune
```

---

## Troubleshooting

```bash
# Restart openclaw
/command/s6-svc -r /run/service/openclaw

# Check if gateway port is listening
ss -tlnp | grep 18789

# Test gateway WebSocket
curl -I http://127.0.0.1:18789

# Re-run config generation
/etc/cont-init.d/20-setup-openclaw

# Check service dependencies
ls /etc/services.d/*/dependencies.d/
```

---

## Common Issues & Fixes

| Issue | Fix |
|-------|-----|
| "Gateway token not configured" | `jq .gateway.auth.token /data/.openclaw/openclaw.json` |
| WhatsApp disconnected after restart | `openclaw channels login` (re-scan QR) or check if backup restored state |
| ngrok tunnel not accessible | `curl http://127.0.0.1:4040/api/tunnels` then restart |
| Command not found (as root) | Use `openclaw` wrapper instead of `openclaw` |
| Backup not running | Check: `ps aux \| grep restic-backup` and logs in `/proc/1/fd/1` |
| Data lost after restart | Verify `ENABLE_SPACES=true` and check `restic snapshots` |
