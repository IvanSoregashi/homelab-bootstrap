# homelab-bootstrap

Collection of reusable Debian bootstrapping scripts for my homelab servers.
Initially developed for **Utsuwa** (storage/NAS node) but structured to be
useful for any Debian server I set up.

## Contents

```
├── bootstrap.sh          # Secrets bootstrap via Bitwarden CLI
├── old_utsuwa/           # Utsuwa-specific provisioning scripts
│   ├── setup-drives.sh   # Interactive disk/ZFS/ext4 wizard
│   ├── setup-dirs.sh     # Directory scaffolding + app setup
│   ├── harden-mmc.sh     # eMMC/SSD write-reduction hardening
│   └── helpers/          # ZFS, ext4, Docker, app, and hardening helpers
```

## Quick Start (Utsuwa)

```
sudo ./old_utsuwa/setup-drives.sh
sudo ./old_utsuwa/setup-dirs.sh /vault/secure /bulk
sudo ./old_utsuwa/harden-mmc.sh /bulk
./bootstrap.sh
```

## Requirements

- Debian 12+ (Bookworm)
- sudo access
- A Bitwarden or Vaultwarden instance with a "Bootstrap" login item

## Related

A private sibling repository holds node-specific backup scripts, Docker
Compose files, and secrets. This repo stays 100% public-safe.
