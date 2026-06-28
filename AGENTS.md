# Agent Context — homelab-bootstrap

This file helps AI assistants understand the project structure, conventions,
and relationship to other repos.

## Repository Role

**`homelab-bootstrap`** is the **public** repository containing provisioning
scripts for Debian-based homelab servers. Initially scoped to Utsuwa (the
storage node), it is a reusable toolkit intended for any future Debian server
I set up. It must remain 100% public-safe — no secrets, hostnames, IPs, or
personally identifiable information.

## What It Covers

- First-boot secrets bootstrap (Bitwarden → local env/password files).
- Interactive disk setup (ZFS pools, encrypted datasets, ext4 partitions).
- Directory scaffolding, bind-mount abstraction, and app directory creation.
- System hardening (eMMC/SSD write reduction: swap, logs, Docker root).
- Application helpers that create directories and align permissions.

## Sibling Repository

A separate **private** repository (`homelab-private`) contains:

- Node-specific backup scripts (Restic to Backblaze B2, retention policies).
- Docker Compose files for deployed services (Samba, Immich, Syncthing, etc.).
- Server-specific configurations and `.env` files.

The private repo is deployed post-bootstrap on the storage node. This public
repo contains no details about private repo contents beyond that description.

## Naming Conventions

- Filenames: `snake_case.sh`
- Functions: `snake_case()`
- Variables: `UPPER_CASE` for exports/config, `lower_case` for locals
- Indentation: tabs, width 4 (enforced by `.editorconfig`)
- Line endings: LF (all text files), enforced by `.gitattributes`
- Scripts should be idempotent unless marked "interactive"

## Design Constraints

- No hardcoded credentials, tokens, hostnames, IPs, or PII.
- Accept system user, pool names, and mount paths as arguments or config.
- Prefer `/etc/fstab` bind-mount abstraction (`/srv/encrypted`, `/srv/data`)
  over raw pool paths wherever practical.
- A single primary system user (UID 1000) owns all data — no hardcoded
  username, derive it from SUDO_USER or UID.

## Key Architectural Patterns

1. **Storage Abstraction Layer:** Physical pool paths are bind-mounted to
   standardized paths (`/srv/encrypted`, `/srv/data`). Containers and backup
   scripts reference these, not raw pool paths. This makes the stack portable
   to single-disk VPS or fallback hardware.

2. **Single User Model:** A primary non-root system user (UID 1000) owns all
   files across SMB, NFS, and Docker to prevent permission conflicts. The
   username is derived dynamically, not hardcoded.

3. **ZFS Encryption:** High-value data lives in a passphrase-encrypted ZFS
   dataset that must be unlocked manually via SSH after reboot. Bulk data
   (media, books) lives on an unencrypted ext4 volume that auto-mounts.

4. **Secrets Bootstrap Flow:** `bootstrap.sh` fetches credentials from
   Bitwarden/Vaultwarden (with local → cloud fallback), writes them to the
   encrypted ZFS volume with strict permissions (chmod 400), then logs out
   and wipes all session data from RAM.

## Current State

The repo is mid-refactor. The `old_utsuwa/` directory contains the original
monolithic scripts. Future work will reorganize into:

```
├── bootstrap.sh
├── scripts/           # setup-drives, setup-directories, harden-system, install-docker
├── lib/               # common, zfs, ext4 helper functions
├── apps/              # per-application directory setup scripts
├── AGENTS.md
└── README.md
```
