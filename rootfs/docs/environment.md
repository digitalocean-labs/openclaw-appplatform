# Environment Variables

How environment variables are managed in the OpenClaw container using s6-overlay.

## Overview

The container uses [s6-overlay](https://github.com/just-containers/s6-overlay) for process supervision. Environment variables passed at runtime need to be persisted to `/run/s6/container_environment/` to be available to s6 services.

## How It Works

1. Container starts, init scripts run
2. All env vars are dumped to `/run/s6/container_environment/`
3. Variables are organized by prefix into subdirectories
4. [Permissions](./permissions.md) are applied from config

### Directory Structure

Variables are stored both at the root (for `with-contenv`) and in prefix subdirectories (for selective `s6-envdir` loading):

```
/run/s6/container_environment/
├── MYPREFIX_/
│   ├── MYPREFIX_VAR1
│   └── MYPREFIX_VAR2
├── MYPREFIX_VAR1     # also at root
└── MYPREFIX_VAR2     # also at root
```

## Helper Library

The shared library at `/etc/s6-overlay/lib/env-utils.sh` provides functions for managing environment variables.

| Function             | Description                                                                 | Example                                      |
| -------------------- | --------------------------------------------------------------------------- | -------------------------------------------- |
| `persist_env_prefix` | Write all env vars matching prefixes to container environment               | `persist_env_prefix FOO_ BAR_`               |
| `persist_env_var`    | Write specific vars to a prefix dir, with optional defaults if unset        | `persist_env_var FOO_ VAR1 VAR2=default`     |
| `persist_env_global` | Write vars to all existing prefix dirs, with optional defaults              | `persist_env_global VAR1 VAR2=default`       |
| `source_env_prefix`  | Export vars from prefix directories into current shell                      | `source_env_prefix FOO_`                     |
| `with_env_prefix`    | Load prefix dirs then exec a command                                        | `with_env_prefix FOO_ -- mycommand`          |
| `apply_permissions`  | Apply file permissions from YAML config                                     | `apply_permissions`                          |

## s6 Commands Reference

| Command                    | Purpose                                    |
| -------------------------- | ------------------------------------------ |
| `with-contenv cmd`         | Run cmd with all container env vars loaded |
| `s6-envdir <dir> cmd`      | Load vars from directory, then run cmd     |
| `s6-dumpenv <dir>`         | Write all current env vars to directory    |
| `s6-dumpenv -m 0600 <dir>` | Write with specific file permissions       |

## File Permissions

Environment files are created with mode `0600` (root read/write only) by default. See [permissions.md](permissions.md) for customization.

## Related Files

- `/etc/cont-init.d/` - Init scripts that persist environment variables
- `/etc/s6-overlay/lib/env-utils.sh` - Shared helper functions
- `/etc/digitalocean/permissions.yaml` - Permission configuration
