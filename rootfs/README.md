# Root Filesystem Overlay

Files in this directory are copied to `/` in the container at the end of the build.

This allows you to add or override any files in the container filesystem.

## Examples

```
rootfs/
├── etc/
│   ├── ssh/
│   │   └── sshd_config.d/
│   │       └── 10-custom.conf     → /etc/ssh/sshd_config.d/10-custom.conf
│   └── motd                        → /etc/motd
└── home/
    └── clawdbot/
        └── .bashrc                 → /home/clawdbot/.bashrc
```

## Notes

- Files are copied with `COPY rootfs/ /` which preserves directory structure
- Existing files in the container will be overwritten
- File permissions from the source are preserved
