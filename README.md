# homelab-bootstrap

Provisioning scripts for Debian-based homelab servers. Initially scoped to
**Utsuwa** (storage/NAS node) but structured to be reusable for any Debian
server.

## Contents

```
├── bootstrap.sh             # Secrets bootstrap (Bitwarden → local env files)
├── setup-utsuwa.sh          # Full Utsuwa setup orchestrator
├── scripts/                 # setup-drives, setup-directories, optimize-system,
│                            # install-docker, install-bw, install-restic,
│                            # install-tailscale, clone-private-repo, restore-backup
├── lib/                     # common, platform, docker, ram, journal, atime,
│                            # zfs, ext4, system_optimizations helpers
└── old_utsuwa/              # Pre-refactor scripts (reference only)
```

## Quick Start (Utsuwa)

```bash
sudo ./setup-utsuwa.sh
```

Or run individual steps:

```bash
sudo ./scripts/setup-drives.sh          # Interactive disk/ZFS/ext4 wizard
sudo ./scripts/setup-directories.sh /vault/secure /bulk   # Directory + app setup
sudo ./scripts/optimize-system.sh /bulk # eMMC/SSD write-reduction
sudo ./bootstrap.sh                     # Secrets from Bitwarden
```

## Requirements

- Debian 12+ (Bookworm)
- sudo access
- Bitwarden or Vaultwarden instance with a "Utsuwa-Bootstrap" login item

## Related

A private sibling repository (`homelab-private`) holds node-specific backup
scripts, Docker Compose files, and secrets. This repo stays 100% public-safe.
