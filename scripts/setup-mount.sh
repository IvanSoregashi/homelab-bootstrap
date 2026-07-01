#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/platform.sh"

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
header "               MOUNT EXISTING DEVICE"
echo -e "Target Path: ${GREEN}${TARGET_PATH}${NC}"
echo -e "System User: ${GREEN}${SYS_USER}${NC}"
echo ""

# --- Scan for mountable partitions ---
echo -e "${BOLD}Scanning for unmounted filesystems...${NC}"
subheader

declare -a mountable_devices=()
declare -a mountable_labels=()

# Scan for unmounted partition devices with a known filesystem
for dev in /dev/sd*[0-9] /dev/nvme*n*p*[0-9] /dev/vd*[0-9] /dev/mmcblk*p*[0-9] /dev/xvd*[0-9]; do
	[ -b "$dev" ] || continue

	fstype=$(blkid -o value -s TYPE "$dev" 2>/dev/null || true)
	[ -z "$fstype" ] && continue

	# Skip known non-data filesystems
	case "$fstype" in
		swap|vfat|fat16|fat32|zfs_member|crypto_LUKS|LVM2_member)
			continue ;;
	esac

	# Skip if already mounted
	mountpoint=$(findmnt -n -o TARGET "$dev" 2>/dev/null || true)
	[ -n "$mountpoint" ] && continue

	size=$(lsblk -dno SIZE "$dev" 2>/dev/null || echo "")
	label=$(blkid -o value -s LABEL "$dev" 2>/dev/null || true)

	mountable_devices+=("${dev};${fstype};${size};${label:-unnamed}")
done

num_mountable=${#mountable_devices[@]}

if [ "$num_mountable" -eq 0 ]; then
	error "No unmounted filesystem partitions found."
	echo "  Connect a drive or create a partition first."
	exit 1
fi

# --- Display ---
printf "  %-4s  %-16s  %-8s  %-10s  %s\n" "ID" "Device" "Size" "FSType" "Label"
subheader
idx=1
for entry in "${mountable_devices[@]}"; do
	IFS=';' read -r dev fst size label <<< "$entry"
	printf "  %-4d  %-16s  %-8s  %-10s  %s\n" "$idx" "$dev" "$size" "$fst" "${label:-}"
	idx=$((idx + 1))
done
subheader
echo ""

# --- User selection ---
read -r -p "Select a device by ID [1-${num_mountable}]: " device_id
[ -z "$device_id" ] && echo "  Returning to menu." && exit 0

if ! [[ "$device_id" =~ ^[0-9]+$ ]] || [ "$device_id" -lt 1 ] || [ "$device_id" -gt "$num_mountable" ]; then
	error "Invalid selection."
	exit 1
fi

selected_entry="${mountable_devices[$((device_id - 1))]}"
IFS=';' read -r SELECTED_DEV SELECTED_FS SELECTED_SIZE SELECTED_LABEL <<< "$selected_entry"

echo -e "Selected: ${CYAN}${SELECTED_DEV}${NC} (${SELECTED_FS}, ${SELECTED_SIZE})"
echo ""

# --- Get persistent path ---
PART_BY_ID=$(get_disk_by_id "$(basename "$SELECTED_DEV")")
echo -e "Persistent Path: ${GREEN}${PART_BY_ID}${NC}"

# --- Check target path ---
if [ -d "$TARGET_PATH" ] && [ "$(ls -A "$TARGET_PATH" 2>/dev/null | wc -l)" -gt 0 ]; then
	echo -e "${YELLOW}Warning: ${TARGET_PATH} is not empty.${NC}"
	read -r -p "Mount anyway? Existing files will be hidden. (y/n) [n]: " mount_anyway
	mount_anyway=${mount_anyway:-n}
	if [[ ! "$mount_anyway" =~ ^[Yy]$ ]]; then
		echo -e "${YELLOW}Cancelled.${NC}"
		exit 0
	fi
fi

if ! [ -d "$TARGET_PATH" ]; then
	echo "--> Creating mount directory: ${TARGET_PATH}"
	mkdir -p "$TARGET_PATH"
fi

if mountpoint -q "$TARGET_PATH"; then
	echo -e "${YELLOW}Warning: ${TARGET_PATH} is already mounted.${NC}"
	read -r -p "Unmount and remount? (y/n) [n]: " do_remount
	do_remount=${do_remount:-n}
	if [[ "$do_remount" =~ ^[Yy]$ ]]; then
		umount "$TARGET_PATH" || true
	else
		echo -e "${YELLOW}Cancelled.${NC}"
		exit 0
	fi
fi

# --- Mount ---
echo "--> Mounting to ${TARGET_PATH}..."
run mount "$PART_BY_ID" "$TARGET_PATH"
echo -e "${GREEN}✔ Mounted at ${TARGET_PATH}.${NC}"

# --- fstab ---
read -r -p "Configure automatic mounting on boot in /etc/fstab? (y/n) [y]: " configure_fstab
configure_fstab=${configure_fstab:-y}
if [[ "$configure_fstab" =~ ^[Yy]$ ]]; then
	if grep -qF "$TARGET_PATH" /etc/fstab 2>/dev/null; then
		echo -e "${YELLOW}An entry for ${TARGET_PATH} already exists in /etc/fstab. Skipping.${NC}"
	else
		echo "${PART_BY_ID} ${TARGET_PATH} ${SELECTED_FS} defaults 0 2" | run tee -a /etc/fstab > /dev/null
		echo -e "${GREEN}✔ fstab entry added.${NC}"
	fi
fi

# --- Permissions ---
echo -e "--> Setting ownership to ${GREEN}${SYS_USER}${NC}..."
run chown -R "${SYS_USER}:${SYS_USER}" "$TARGET_PATH"

echo -e "\n${GREEN}✔ Device mounted successfully!${NC}"
echo -e "  Device:      ${PART_BY_ID}"
echo -e "  Filesystem:  ${SELECTED_FS}"
echo -e "  Mount Point: ${TARGET_PATH}"
