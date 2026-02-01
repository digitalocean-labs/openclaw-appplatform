# File Permissions

How file permissions are managed in the OpenClaw container.

## Overview

File permissions are declared in [`/etc/digitalocean/permissions.yaml`](../etc/digitalocean/permissions.yaml) and applied:

1. **Build time** - Dockerfile applies permissions to static paths
2. **Runtime** - Init scripts apply permissions to dynamic paths and also reapply the static ones for consistency

## Configuration

Permissions are defined in [`/etc/digitalocean/permissions.yaml`](../etc/digitalocean/permissions.yaml) .

Each entry supports:

| Field   | Description                              | Example                   |
| ------- | ---------------------------------------- | ------------------------- |
| `path`  | File or glob pattern                     | `/docs/*`, `/run/s6/**/*` |
| `mode`  | Unix permission mode                     | `"0644"`, `"0755"`        |
| `user`  | Owner user                               | `root`, `openclaw`        |
| `group` | Owner group                              | `root`, `openclaw`        |
| `umask` | Umask for new files created in this path | `"0077"`, `"0022"`        |

## Order Matters

Permissions are applied in order. Later entries override earlier ones for matching paths.

## Glob Patterns

| Pattern | Matches                |
| ------- | ---------------------- |
| `*`     | Any files in directory |
| `**/*`  | All files recursively  |
| `*.txt` | Files ending in .txt   |

## Common Permission Modes

| Mode   | Meaning                                       |
| ------ | --------------------------------------------- |
| `0444` | Read-only for all                             |
| `0555` | Read + execute for all (directories)          |
| `0600` | Read/write owner only                         |
| `0644` | Read/write owner, read others                 |
| `0700` | Read/write/execute owner only                 |
| `0755` | Read/write/execute owner, read/execute others |

## When Applied

- **Build time**: Static paths (`/docs`, `/etc/s6-overlay/lib`)
- **Runtime**: Dynamic paths (`/run/s6/container_environment/`)

## Warnings

The `apply_permissions` function emits warnings when paths don't exist or patterns match nothing.

## Related Files

- [`/etc/digitalocean/permissions.yaml`](../etc/digitalocean/permissions.yaml)  - Permission configuration
- [`/etc/s6-overlay/lib/env-utils.sh`](../etc/s6-overlay/lib/env-utils.sh) - Contains `apply_permissions` function
- [`/etc/cont-init.d/00-persist-env-vars`](../etc/cont-init.d/00-persist-env-vars) - Calls `apply_permissions` at runtime
