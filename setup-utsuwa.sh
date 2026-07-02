#!/bin/bash
# ==============================================================================
# Utsuwa: Full System Setup Orchestrator
#
# Runs the complete setup flow for a Utsuwa storage node:
#   1. Ensure storage paths (/srv/encrypted, /srv/data)
#   2. Create directory structure + app directories
#   3. Bootstrap secrets from Bitwarden
#   4. Install Restic
#   5. Clone private repository (Docker Compose, configs)
#   6. Connect to Tailnet
#   7. System optimization (eMMC write reduction)
#   8. Restore from backup
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
# Step 1: Ensure storage paths exist
# ------------------------------------------------------------------
echo -e "${BOLD}[1/7] Storage Path Verification${NC}"

paths=(/srv/encrypted /srv/data)
labels=("Encrypted volume" "Data volume")

while true; do
    all_exist=true
    for i in "${!paths[@]}"; do
        path="${paths[$i]}"
        label="${labels[$i]}"

        if [ -d "$path" ]; then
            echo -e "  ${GREEN}✔${NC} ${label} (${path}) exists."
            continue
        fi

        all_exist=false
        echo -e "\n  ${YELLOW}${label} (${path}) does not exist.${NC}"
        echo "    Choose action:"
        echo "      1) Create and mount ZFS pool/dataset (${path})"
        echo "      2) Create and mount ext4 partition (${path})"
        echo "      3) Mount existing drive (${path})"
        echo "      4) Create directory (${path})"
        echo "      5) Wait and retry"
        read -r choice

        case $choice in
            1)
                bash "${SCRIPT_DIR}/scripts/setup-zfs.sh" "$path"
                ;;
            2)
                bash "${SCRIPT_DIR}/scripts/setup-ext4.sh" "$path"
                ;;
            3)
                bash "${SCRIPT_DIR}/scripts/setup-mount.sh" "$path"
                ;;
            4)
                mkdir -p "$path"
                ;;
            5)
                echo "  Waiting 5 seconds before retry..."
                sleep 5
                ;;
        esac

        break
    done

    $all_exist && break
done

echo -e "  ${GREEN}All storage paths are ready.${NC}"

SECURE_SRC=/srv/encrypted
DATA_SRC=/srv/data

# ------------------------------------------------------------------
# Step 2: Create directory structure
# ------------------------------------------------------------------
echo -e "\n${BOLD}[2/7] Directory Setup${NC}"

bash "${SCRIPT_DIR}/scripts/setup-directories.sh" "$SECURE_SRC" "$DATA_SRC"
echo -e "  ${GREEN}✔${NC} Directories initialized."

# ------------------------------------------------------------------
# Step 3: Install prerequisites and bootstrap secrets
# ------------------------------------------------------------------
echo -e "\n${BOLD}[3/7] Secrets Bootstrap${NC}"

bash "${SCRIPT_DIR}/scripts/bootstrap.sh"
echo -e "  ${GREEN}✔${NC} Secrets bootstrapped."

# ------------------------------------------------------------------
# Step 4: Install Restic
# ------------------------------------------------------------------
echo -e "\n${BOLD}[4/7] Backup Tool Installation${NC}"

source "${SCRIPT_DIR}/lib/restic.sh"
install_restic
echo -e "  ${GREEN}✔${NC} Restic installed."

# ------------------------------------------------------------------
# Step 5: Clone private repository
# ------------------------------------------------------------------
echo -e "\n${BOLD}[5/7] Private Repository Clone${NC}"

read -r -p "  What is your GitHub username? [ivan]: " GITHUB_USER
GITHUB_USER=${GITHUB_USER:-ivan}

read -r -p "  Clone the homelab-private repository? (y/n) [n]: " clone_repo
clone_repo=${clone_repo:-n}
if [[ "$clone_repo" =~ ^[Yy]$ ]]; then
    bash "${SCRIPT_DIR}/scripts/clone-private-repo.sh" "$GITHUB_USER"
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
    source "${SCRIPT_DIR}/lib/tailscale.sh"
    install_tailscale

    TAILSCALE_KEY_FILE="/srv/encrypted/apps/restic/tailscale-key"
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
# Restore from backup
# ------------------------------------------------------------------
echo ""
read -r -p "  Restore data from Restic backup now? (y/n) [n]: " restore_now
restore_now=${restore_now:-n}
if [[ "$restore_now" =~ ^[Yy]$ ]]; then
    bash "${SCRIPT_DIR}/scripts/restore-backup.sh"
fi

# ------------------------------------------------------------------
echo -e "\n${GREEN}${BOLD}✔ Utsuwa setup complete!${NC}"
echo -e "  Review the steps above for any manual actions needed."
echo -e "  Next steps: deploy Docker Compose from the private repo."
echo ""
