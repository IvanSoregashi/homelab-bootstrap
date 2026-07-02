#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/platform.sh"
source "${SCRIPT_DIR}/../lib/directory_layout.sh"

# --- Argument Validation ---
if [ "$#" -ne 2 ]; then
    error "Missing required paths."
    echo "Usage: $0 <path_to_secure_volume> <path_to_data_volume>"
    echo "Example: $0 /vault/secure /bulk"
    exit 1
fi

if [ ! -d "$1" ] || [ ! -d "$2" ]; then
    error "One or both of the provided directory paths do not exist on the filesystem."
    echo "Please ensure the paths exist (create them or mount the storage)."
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

# --- Consolidated Directory Creation ---
echo -e "\n--> Creating directory structure..."

for dir in "${SECURE_DIRS[@]}"; do
    mkdir -p "$dir"
done

for dir in "${DATA_DIRS[@]}"; do
    mkdir -p "$dir"
done

# --- Permission Alignment ---
echo -e "\n--> Aligning permissions..."
chown -R "${SYS_USER}:${SYS_USER}" "${SECURE_PATH}" || true
chown -R "${SYS_USER}:${SYS_USER}" "${DATA_PATH}" || true

echo -e "\n======================================================================"
echo -e "${GREEN}✔ Initialization Complete!${NC}"
echo -e "  /srv/encrypted  -> $SECURE_PATH"
echo -e "  /srv/data       -> $DATA_PATH"
echo -e "======================================================================\n"
