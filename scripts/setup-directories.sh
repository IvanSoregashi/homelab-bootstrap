#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/platform.sh"

# --- Argument Validation ---
if [ "$#" -ne 2 ]; then
    error "Missing required paths."
    echo "Usage: $0 <path_to_secure_volume> <path_to_data_volume>"
    echo "Example: $0 /vault/secure /bulk"
    exit 1
fi

if [ ! -d "$1" ] || [ ! -d "$2" ]; then
    error "One or both of the provided directory paths do not exist on the filesystem."
    echo "Please ensure the storage pools are mounted."
    exit 1
fi

SECURE_PATH=$(realpath "$1")
DATA_PATH=$(realpath "$2")
SYS_USER=$(detect_user)

header "                 DIRECTORY SETUP"
echo -e "Secure Path: ${GREEN}$SECURE_PATH${NC}"
echo -e "Data Path:   ${GREEN}$DATA_PATH${NC}"
echo -e "System User: ${GREEN}$SYS_USER${NC}"

# --- Mount Safety Verification ---
echo "--> Verifying drive mount safety..."
check_mount_safety "$SECURE_PATH" "Secure"
check_mount_safety "$DATA_PATH" "Data"

# --- Setup Standardized /srv Bind Mounts ---
echo -e "\n--> Preparing standardized /srv bind mounts..."
mkdir -p /srv/encrypted /srv/data

add_fstab_bind "$SECURE_PATH" "/srv/encrypted"
add_fstab_bind "$DATA_PATH" "/srv/data"

# --- Mount the new paths ---
echo "--> Mounting standardized /srv layers..."

if ! mountpoint -q /srv/encrypted; then
    mount /srv/encrypted || echo -e "${YELLOW}Warning: /srv/encrypted could not mount (is the pool locked?)${NC}"
else
    echo "  /srv/encrypted is already mounted."
fi

if ! mountpoint -q /srv/data; then
    mount /srv/data || echo -e "${YELLOW}Warning: /srv/data could not mount.${NC}"
else
    echo "  /srv/data is already mounted."
fi

# --- Consolidated Directory Creation ---
echo -e "\n--> Creating directory structure..."

# Tier 1: Encrypted (core data)
mkdir -p "${SECURE_PATH}/vault"
mkdir -p "${SECURE_PATH}/archive"
mkdir -p "${SECURE_PATH}/webdav"
mkdir -p "${SECURE_PATH}/db-dumps"
mkdir -p "${SECURE_PATH}/apps/restic"
mkdir -p "${SECURE_PATH}/apps/syncthing"
mkdir -p "${SECURE_PATH}/apps/calibre-config"
mkdir -p "${SECURE_PATH}/apps/immich/db"

# Tier 2: Bulk (data)
mkdir -p "${DATA_PATH}/gallery/immich"
mkdir -p "${DATA_PATH}/books"
mkdir -p "${DATA_PATH}/downloads"
mkdir -p "${DATA_PATH}/backups"

# --- Permission Alignment ---
echo -e "\n--> Aligning permissions..."
chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}" || true
chown -R "${SYS_USER}:${SYS_USER}" "${DATA_PATH}" || true

echo -e "\n======================================================================"
echo -e "${GREEN}✔ Initialization Complete!${NC}"
echo -e "  /srv/encrypted  -> $SECURE_PATH"
echo -e "  /srv/data       -> $DATA_PATH"
echo -e "======================================================================\n"
