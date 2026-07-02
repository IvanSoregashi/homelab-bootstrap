#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/platform.sh"
source "${SCRIPT_DIR}/../lib/drive.sh"
source "${SCRIPT_DIR}/../lib/ext4.sh"

require_root
SYS_USER=$(detect_user)

# --- Argument validation ---
if [ "$#" -ne 1 ]; then
	error "Missing target path."
	echo "Usage: $0 <target_mount_path>"
	echo "Example: $0 /srv/data"
	exit 1
fi

TARGET_PATH="$1"
header "               EXT4 PARTITION SETUP"
echo -e "Target Path: ${GREEN}${TARGET_PATH}${NC}"
echo -e "System User: ${GREEN}${SYS_USER}${NC}"
echo ""

# --- Ensure tools ---
ext4_ensure_tools

# --- Scan disks ---
suitable_disks=()
display_fs_diagnostics suitable_disks
num_disks=${#suitable_disks[@]}

if [ "$num_disks" -eq 0 ]; then
	error "No suitable disks found."
	exit 1
fi

display_suitable_disks suitable_disks

# --- Disk selection ---
read -r -p "Select a disk by ID [1-${num_disks}]: " disk_id
[ -z "$disk_id" ] && echo "  Returning to menu." && exit 0

if ! [[ "$disk_id" =~ ^[0-9]+$ ]] || [ "$disk_id" -lt 1 ] || [ "$disk_id" -gt "$num_disks" ]; then
	error "Invalid selection."
	exit 1
fi

selected_entry="${suitable_disks[$((disk_id - 1))]}"
IFS=';' read -r selected_disk _ model <<< "$selected_entry"

# Resolve persistent disk path
DISK_BY_ID=$(get_disk_by_id "$selected_disk")
echo -e "Persistent Disk Path: ${GREEN}${DISK_BY_ID}${NC}"
echo -e "Model: ${model}"
echo ""

# --- Warning & Confirmation ---
echo -e "${RED}${BOLD}!!! WARNING !!! WARNING !!! WARNING !!!${NC}"
echo -e "${RED}This operation will DESTROY all data on ${DISK_BY_ID}.${NC}"
read -r -p "Type 'yes' to proceed, or anything else to abort: " confirm_wipe

if [ "$confirm_wipe" != "yes" ]; then
	echo -e "${YELLOW}Cancelled.${NC}"
	exit 0
fi

# --- Provision ---
echo -e "\n${YELLOW}${BOLD}⚠ PROVISIONING IN PROGRESS${NC}"
echo -e "${YELLOW}Disk state is being modified. Interrupting may require manual cleanup.${NC}"

echo -e "\n--> Creating GPT Partition Table..."
ext4_create_partition "$DISK_BY_ID"

echo "--> Waiting for partition creation..."
sleep 2

# --- Find partition ---
PART_NAME=$(ext4_find_partition "$selected_disk")
if [ -z "$PART_NAME" ]; then
	error "Could not locate the newly created partition device."
	exit 1
fi

PART_BY_ID=$(get_disk_by_id "$PART_NAME")
echo -e "Detected partition: ${GREEN}/dev/${PART_NAME}${NC} -> ${GREEN}${PART_BY_ID}${NC}"

# --- Format ---
echo -e "\n--> Formatting as ext4..."
ext4_format "$PART_BY_ID"

# --- Mount ---
if [ ! -d "$TARGET_PATH" ]; then
	echo "--> Creating mount directory: ${TARGET_PATH}"
	mkdir -p "$TARGET_PATH"
fi

if mountpoint -q "$TARGET_PATH"; then
	echo -e "${YELLOW}Warning: ${TARGET_PATH} is already mounted.${NC}"
	echo -e "${YELLOW}Note: The partition was already created and formatted.${NC}"
	read -r -p "Unmount and remount? (y/n) [n]: " do_remount
	do_remount=${do_remount:-n}
	if [[ "$do_remount" =~ ^[Yy]$ ]]; then
		umount "$TARGET_PATH" || true
	else
		echo "  The partition exists but is not mounted at ${TARGET_PATH}."
		exit 0
	fi
fi

echo "--> Mounting partition to ${TARGET_PATH}..."
ext4_mount "$PART_BY_ID" "$TARGET_PATH"

# --- fstab ---
read -r -p "Configure automatic mounting on boot in /etc/fstab? (y/n) [y]: " configure_fstab
configure_fstab=${configure_fstab:-y}
if [[ "$configure_fstab" =~ ^[Yy]$ ]]; then
	ext4_setup_fstab "$PART_BY_ID" "$TARGET_PATH"
fi

# --- Permissions ---
echo -e "--> Setting ownership to ${GREEN}${SYS_USER}${NC}..."
run chown -R "${SYS_USER}:${SYS_USER}" "$TARGET_PATH"

echo -e "\n${GREEN}✔ Ext4 Partition successfully created!${NC}"
echo -e "  Device:      ${PART_BY_ID}"
echo -e "  Mount Point: ${TARGET_PATH}"
