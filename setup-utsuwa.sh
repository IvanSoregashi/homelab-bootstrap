#!/bin/bash
# ==============================================================================
# Utsuwa: Full System Setup Orchestrator
#
# Runs the complete setup flow for a Utsuwa storage node:
#   1. Ensure storage mounts (/srv/encrypted, /srv/data)
#   2. Create directory structure + app directories
#   3. Bootstrap secrets from Bitwarden
#   4. Install Restic and optionally restore from backup
#   5. Clone private repository (Docker Compose, configs)
#   6. Connect to Tailnet
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/platform.sh"

require_root
SYS_USER=$(detect_user)

header "                  UTSUWA SETUP ORCHESTRATOR"
echo -e "  System User: ${GREEN}${SYS_USER}${NC}"
echo ""

# ------------------------------------------------------------------
# Step 1: Ensure storage mounts are present
# ------------------------------------------------------------------
echo -e "${BOLD}[1/7] Storage Mount Verification${NC}"

ensure_mount() {
    local path="$1"
    local label="$2"

    if mountpoint -q "$path"; then
        echo -e "  ${GREEN}✔${NC} ${label} (${path}) is mounted."
        return 0
    fi
    return 1
}

if ensure_mount /srv/encrypted "Encrypted volume" && ensure_mount /srv/data "Data volume"; then
    echo -e "  ${GREEN}All storage mounts are ready.${NC}"
else
    echo -e "\n  ${YELLOW}Storage mounts are not fully set up.${NC}"
    read -r -p "  Run the drive/interactive setup wizard? (y/n) [y]: " run_drives
    run_drives=${run_drives:-y}

    if [[ "$run_drives" =~ ^[Yy]$ ]]; then
        bash "${SCRIPT_DIR}/scripts/setup-drives.sh"
    fi

    # Re-check after wizard
    echo -e "\n  ${BOLD}Re-verifying mounts...${NC}"
    if ! ensure_mount /srv/encrypted "Encrypted volume" || ! ensure_mount /srv/data "Data volume"; then
        echo -e "\n  ${BOLD}Attempting to mount from fstab...${NC}"
        mount /srv/encrypted 2>/dev/null || true
        mount /srv/data 2>/dev/null || true
    fi

    if ! ensure_mount /srv/encrypted "Encrypted volume" || ! ensure_mount /srv/data "Data volume"; then
        echo -e "\n${RED}${BOLD}CRITICAL:${NC} Storage mounts are still not available."
        echo "  /srv/encrypted and /srv/data must be mounted to proceed."
        echo "  If using encrypted ZFS, unlock and mount manually via SSH."
        exit 1
    fi

    # Resolve source paths for app setup
    SECURE_SRC=$(findmnt -n -o SOURCE --target /srv/encrypted 2>/dev/null | sed 's/\[.*\]//' || echo "/srv/encrypted")
    DATA_SRC=$(findmnt -n -o SOURCE --target /srv/data 2>/dev/null | sed 's/\[.*\]//' || echo "/srv/data")
fi

# Determine pool paths for app scripts
SECURE_SRC=${SECURE_SRC:-/srv/encrypted}
DATA_SRC=${DATA_SRC:-/srv/data}

# ------------------------------------------------------------------
# Step 2: Create directory structure and app directories
# ------------------------------------------------------------------
echo -e "\n${BOLD}[2/7] Directory & Application Setup${NC}"

AUTO_APPS=true bash "${SCRIPT_DIR}/scripts/setup-directories.sh" "$SECURE_SRC" "$DATA_SRC"
echo -e "  ${GREEN}✔${NC} Directories initialized."

# ------------------------------------------------------------------
# Step 3: Install prerequisites and bootstrap secrets
# ------------------------------------------------------------------
echo -e "\n${BOLD}[3/7] Secrets Bootstrap${NC}"

source "${SCRIPT_DIR}/scripts/install-bw.sh"
install_bw

bash "${SCRIPT_DIR}/bootstrap.sh"
echo -e "  ${GREEN}✔${NC} Secrets bootstrapped."

# ------------------------------------------------------------------
# Step 4: Install Restic and optionally restore
# ------------------------------------------------------------------
echo -e "\n${BOLD}[4/7] Backup Tool Installation${NC}"

source "${SCRIPT_DIR}/scripts/install-restic.sh"
install_restic
echo -e "  ${GREEN}✔${NC} Restic installed."

echo ""
read -r -p "  Restore data from Restic backup now? (y/n) [n]: " restore_now
restore_now=${restore_now:-n}
if [[ "$restore_now" =~ ^[Yy]$ ]]; then
    bash "${SCRIPT_DIR}/scripts/restore-backup.sh"
fi

# ------------------------------------------------------------------
# Step 5: Clone private repository
# ------------------------------------------------------------------
echo -e "\n${BOLD}[5/7] Private Repository Clone${NC}"

read -r -p "  Clone the homelab-private repository? (y/n) [n]: " clone_repo
clone_repo=${clone_repo:-n}
if [[ "$clone_repo" =~ ^[Yy]$ ]]; then
    bash "${SCRIPT_DIR}/scripts/clone-private-repo.sh"
fi

# ------------------------------------------------------------------
# Step 6: Connect to Tailnet
# ------------------------------------------------------------------
echo -e "\n${BOLD}[6/7] Tailnet Connection${NC}"

# Only prompt for Tailscale if not on a local network
echo -e "  Is this server on your local network (direct LAN access),"
echo -e "  or does it need a Tailscale connection for remote access?"
read -r -p "  Install and connect Tailscale? (y/n) [n]: " setup_ts
setup_ts=${setup_ts:-n}

if [[ "$setup_ts" =~ ^[Yy]$ ]]; then
    source "${SCRIPT_DIR}/scripts/install-tailscale.sh"
    install_tailscale

    TAILSCALE_KEY_FILE="/srv/encrypted/app/restic/tailscale-key"
    if [ -f "$TAILSCALE_KEY_FILE" ]; then
        echo "  Found Tailscale auth key. Connecting..."
        tailscale up --authkey="$(cat "$TAILSCALE_KEY_FILE")"
    else
        echo -e "  ${YELLOW}No Tailscale auth key found.${NC}"
        echo "  Connect manually with: sudo tailscale up"
    fi
fi

# ------------------------------------------------------------------
# Step 7: Final system optimization (Debian)
# ------------------------------------------------------------------
echo -e "\n${BOLD}[7/7] System Optimization${NC}"

if os_is_debian; then
    read -r -p "  Run system optimization (eMMC write reduction)? (y/n) [y]: " run_opt
    run_opt=${run_opt:-y}
    if [[ "$run_opt" =~ ^[Yy]$ ]]; then
        bash "${SCRIPT_DIR}/scripts/optimize-system.sh" "$DATA_SRC"
    fi
fi

# ------------------------------------------------------------------
echo -e "\n${GREEN}${BOLD}✔ Utsuwa setup complete!${NC}"
echo -e "  Review the steps above for any manual actions needed."
echo -e "  Next steps: deploy Docker Compose from the private repo."
echo ""
