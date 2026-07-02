#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/platform.sh"
source "${SCRIPT_DIR}/../lib/drive.sh"
source "${SCRIPT_DIR}/../lib/zfs.sh"

require_root
SYS_USER=$(detect_user)

# --- Argument validation ---
if [ "$#" -ne 1 ]; then
	error "Missing target path."
	echo "Usage: $0 <target_mount_path>"
	echo "Example: $0 /srv/encrypted"
	exit 1
fi

TARGET_PATH="$1"
header "                 ZFS POOL SETUP"
echo -e "Target Path: ${GREEN}${TARGET_PATH}${NC}"
echo -e "System User: ${GREEN}${SYS_USER}${NC}"
echo ""

# --- Ensure ZFS installed ---
zfs_ensure_installed

if ! zfs_check_installed; then
	error "ZFS tools are not available."
	exit 1
fi

if ! zfs_module_loaded; then
	echo "--> Loading ZFS kernel module..."
	modprobe zfs || true
fi

# --- Scan disks ---
suitable_disks=()
display_fs_diagnostics suitable_disks
num_disks=${#suitable_disks[@]}

if [ "$num_disks" -eq 0 ]; then
	error "No suitable disks found."
	exit 1
fi

# --- Pick pool type and disk(s) ---
echo "Choose ZFS configuration type:"
echo "  1) Single Disk Pool (No redundancy)"
echo "  2) Mirrored Pool (Requires 2 disks)"
echo "  Leave empty to return to menu"
read -r -p "Select ZFS layout [1-2]: " zfs_choice

[ -z "$zfs_choice" ] && echo "  Returning to menu." && exit 0

case "$zfs_choice" in
	1)
		display_suitable_disks suitable_disks
		read -r -p "Select a disk by ID [1-${num_disks}]: " disk_id
		[ -z "$disk_id" ] && echo "  Returning to menu." && exit 0
		if ! [[ "$disk_id" =~ ^[0-9]+$ ]] || [ "$disk_id" -lt 1 ] || [ "$disk_id" -gt "$num_disks" ]; then
			error "Invalid selection."
			exit 1
		fi
		selected_entry="${suitable_disks[$((disk_id - 1))]}"
		IFS=';' read -r selected_disk _ <<< "$selected_entry"
		;;
	2)
		if [ "$num_disks" -lt 2 ]; then
			error "A mirrored pool requires at least 2 available disks."
			exit 1
		fi
		display_suitable_disks suitable_disks
		read -r -p "Select the FIRST disk by ID [1-${num_disks}]: " disk1_id
		[ -z "$disk1_id" ] && echo "  Returning to menu." && exit 0
		read -r -p "Select the SECOND disk by ID [1-${num_disks}]: " disk2_id
		[ -z "$disk2_id" ] && echo "  Returning to menu." && exit 0
		if [ "$disk1_id" = "$disk2_id" ]; then
			error "You must select two distinct disks."
			exit 1
		fi
		if ! [[ "$disk1_id" =~ ^[0-9]+$ ]] || [ "$disk1_id" -lt 1 ] || [ "$disk1_id" -gt "$num_disks" ] || \
		   ! [[ "$disk2_id" =~ ^[0-9]+$ ]] || [ "$disk2_id" -lt 1 ] || [ "$disk2_id" -gt "$num_disks" ]; then
			error "Invalid selection."
			exit 1
		fi
		disk1_entry="${suitable_disks[$((disk1_id - 1))]}"
		disk2_entry="${suitable_disks[$((disk2_id - 1))]}"
		IFS=';' read -r disk1 _ <<< "$disk1_entry"
		IFS=';' read -r disk2 _ <<< "$disk2_entry"
		;;
	*)
		error "Invalid choice."
		exit 1
		;;
esac

# --- Pool name ---
echo ""
read -r -p "Enter name for the new ZFS pool [default: vault]: " POOL_NAME
POOL_NAME=${POOL_NAME:-vault}

if zpool list "$POOL_NAME" &>/dev/null; then
	error "A ZFS pool named '${POOL_NAME}' already exists."
	exit 1
fi

# --- Encrypted dataset ---
read -r -p "Create an encrypted dataset inside '${POOL_NAME}'? (y/n) [y]: " create_encrypted
create_encrypted=${create_encrypted:-y}

DATASET_NAME=""
if [[ "$create_encrypted" =~ ^[Yy]$ ]]; then
	read -r -p "Enter dataset name [default: secure]: " DATASET_NAME
	DATASET_NAME=${DATASET_NAME:-secure}
fi

# --- ARC limit ---
ARC_RECOMMENDED=$(zfs_calculate_arc)
read -r -p "Configure ZFS RAM limit (ARC cache)? (y/n) [y]: " limit_arc
limit_arc=${limit_arc:-y}

ARC_LIMIT_INPUT=""
if [[ "$limit_arc" =~ ^[Yy]$ ]]; then
	total_ram_gb=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
	echo -e "Total System Memory: ${CYAN}${total_ram_gb} GB${NC}"
	read -r -p "Enter ARC RAM Limit (e.g., 3G, 4G, 512M) [default: ${ARC_RECOMMENDED}]: " ARC_LIMIT_INPUT
	ARC_LIMIT_INPUT=${ARC_LIMIT_INPUT:-$ARC_RECOMMENDED}
fi

# --- Confirmation ---
echo -e "\n${RED}${BOLD}!!! WARNING !!! WARNING !!! WARNING !!!${NC}"
echo -e "${RED}This will DESTROY all data on the selected disk(s).${NC}"
echo ""
echo -e "${BOLD}Setup Summary:${NC}"
echo -e "  Target path: ${GREEN}${TARGET_PATH}${NC}"
echo -e "  Pool Name:   ${GREEN}${POOL_NAME}${NC}"
if [ "$zfs_choice" = "2" ]; then
	echo -e "  Layout:      ${GREEN}MIRROR${NC}"
else
	echo -e "  Layout:      ${GREEN}SINGLE${NC}"
fi
if [[ "$create_encrypted" =~ ^[Yy]$ ]]; then
	echo -e "  Encrypted:   ${GREEN}${POOL_NAME}/${DATASET_NAME}${NC}"
fi
if [[ "$limit_arc" =~ ^[Yy]$ ]] && [ -n "$ARC_LIMIT_INPUT" ]; then
	echo -e "  ARC Limit:   ${GREEN}${ARC_LIMIT_INPUT}${NC}"
fi
echo ""
read -r -p "Type 'yes' to proceed: " confirm_zfs

if [ "$confirm_zfs" != "yes" ]; then
	echo -e "${YELLOW}Cancelled.${NC}"
	exit 0
fi

# --- Provision ---
echo -e "\n${YELLOW}${BOLD}⚠ PROVISIONING IN PROGRESS${NC}"
echo -e "${YELLOW}Disk state is being modified. Interrupting may require manual cleanup.${NC}"

echo -e "\n--> Creating ZFS Pool '${POOL_NAME}'..."

if [ "$zfs_choice" = "2" ]; then
	DISK1_BY_ID=$(get_disk_by_id "$disk1")
	DISK2_BY_ID=$(get_disk_by_id "$disk2")
	zfs_create_pool "$POOL_NAME" "mirror" "$DISK1_BY_ID" "$DISK2_BY_ID"
else
	DISK_BY_ID=$(get_disk_by_id "$selected_disk")
	zfs_create_pool "$POOL_NAME" "single" "$DISK_BY_ID"
fi

echo -e "${GREEN}✔ ZFS Pool '${POOL_NAME}' created.${NC}"

# --- Create encrypted dataset ---
if [[ "$create_encrypted" =~ ^[Yy]$ ]]; then
	echo -e "\n--> Creating Encrypted Dataset..."
	echo -e "${YELLOW}Enter a secure passphrase when prompted.${NC}"
	zfs_create_encrypted_dataset "$POOL_NAME" "$DATASET_NAME"
	echo -e "${GREEN}✔ Encrypted dataset created.${NC}"

	echo -e "\n--> Setting mountpoint to ${TARGET_PATH}..."
	run zfs set mountpoint="$TARGET_PATH" "${POOL_NAME}/${DATASET_NAME}"
else
	echo -e "\n--> Setting mountpoint to ${TARGET_PATH}..."
	run zfs set mountpoint="$TARGET_PATH" "$POOL_NAME"
fi

# --- Configure ARC ---
if [[ "$limit_arc" =~ ^[Yy]$ ]] && [ -n "$ARC_LIMIT_INPUT" ]; then
	ARC_BYTES=$(parse_to_bytes "$ARC_LIMIT_INPUT")
	if [ "$ARC_BYTES" -gt 0 ]; then
		echo -e "\n--> Limiting ARC to ${ARC_LIMIT_INPUT}..."
		zfs_configure_arc "$ARC_BYTES"
		echo -e "${GREEN}✔ ARC limit configured.${NC}"
	fi
fi

# --- Permissions ---
echo -e "\n--> Aligning permissions to ${GREEN}${SYS_USER}${NC}..."
run chown -R "${SYS_USER}:${SYS_USER}" "$TARGET_PATH"

echo -e "\n${GREEN}✔ ZFS Pool provisioned successfully!${NC}"
echo -e "  Mount Point: ${TARGET_PATH}"
