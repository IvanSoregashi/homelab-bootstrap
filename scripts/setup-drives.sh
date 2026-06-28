#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/platform.sh"
source "${SCRIPT_DIR}/../lib/zfs.sh"
source "${SCRIPT_DIR}/../lib/ext4.sh"

require_root
SYS_USER=$(detect_user)
HELPERS_DIR="${SCRIPT_DIR}/helpers"

display_suitable_disks() {
    local -n disk_arr=$1
    echo -e "${BOLD}Suitable / Ready-to-use Disks Found:${NC}"
    subheader
    printf "  %-4s  %-12s  %-10s  %-30s\n" "ID" "Device Name" "Size" "Model / Hardware Details"
    subheader

    local idx=1
    for item in "${disk_arr[@]}"; do
        IFS=';' read -r name size model <<< "$item"
        printf "  %-4d  %-12s  %-10s  %-30s\n" "$idx" "/dev/$name" "$size" "$model"
        idx=$((idx + 1))
    done
    subheader
    echo ""
}

display_fs_diagnostics() {
    local -n suitable_ref=$1
    suitable_ref=()

    echo -e "${BOLD}[SCAN DIAGNOSTICS] Evaluating system storage devices...${NC}"
    subheader

    local raw_disks
    mapfile -t raw_disks < <(lsblk -pdno NAME,SIZE,TYPE 2>/dev/null | grep -w 'disk' || true)

    for row in "${raw_disks[@]}"; do
        [ -z "$row" ] && continue
        local dev_path size type
        read -r dev_path size type <<< "$row"
        local dev_name
        dev_name=$(basename "$dev_path")

        local model
        model=$(lsblk -dno MODEL "$dev_path" 2>/dev/null | xargs || echo "Unknown Model")

        local reasons=()
        analyze_disk_suitability "$dev_name" reasons

        echo -e "Evaluating ${CYAN}/dev/${dev_name}${NC} [${size}] - ${model}:"

        if [ ${#reasons[@]} -eq 0 ]; then
            echo -e "  --> Status: ${GREEN}${BOLD}✔ SUITABLE${NC} (Unused & ready for provisioning)"
            suitable_ref+=("${dev_name};${size};${model}")
        else
            echo -e "  --> Status: ${RED}${BOLD}✘ NOT SUITABLE${NC}"
            echo -e "  --> Reason(s):"
            for r in "${reasons[@]}"; do
                echo -e "      * ${r}"
            done
        fi
        echo ""
    done
    subheader
    echo ""
}

while true; do
    header "                     DISK SETUP WIZARD"
    echo -e "Detected active user: ${GREEN}${SYS_USER}${NC}"
    echo ""

    suitable_disks=()
    display_fs_diagnostics suitable_disks
    num_disks=${#suitable_disks[@]}

    if [ "$num_disks" -eq 0 ]; then
        echo -e "${YELLOW}No unused or unmounted physical disks detected on this system.${NC}"
        echo "Please make sure your drives are connected and not currently in use."
        echo ""
        read -r -p "Press Enter to exit..." _
        exit 0
    fi

    display_suitable_disks suitable_disks

    echo -e "${BOLD}What would you like to configure?${NC}"
    echo "  1) Set up an Ext4 Partition (Single disk - great for bulk/unencrypted storage)"
    echo "  2) Set up a ZFS Storage Pool (Supports mirrors or single disks)"
    echo "  3) Rescan Disks"
    echo "  4) Exit"
    echo ""
    read -r -p "Select option [1-4]: " menu_choice

    case "$menu_choice" in
        1)
            echo ""
            echo -e "${CYAN}--> Preparing Ext4 Partition Setup...${NC}"
            read -r -p "Select a disk by ID [1-${num_disks}]: " disk_id

            if ! [[ "$disk_id" =~ ^[0-9]+$ ]] || [ "$disk_id" -lt 1 ] || [ "$disk_id" -gt "$num_disks" ]; then
                echo -e "${RED}Invalid selection.${NC}"
                read -r -p "Press Enter to return to main menu..." _
                continue
            fi

            selected_entry="${suitable_disks[$((disk_id - 1))]}"
            IFS=';' read -r selected_disk _ model <<< "$selected_entry"

            # Resolve persistent disk path
            DISK_BY_ID=$(get_disk_by_id "$selected_disk")
            echo -e "Persistent Disk Path: ${GREEN}${DISK_BY_ID}${NC}"
            echo -e "Model: ${model}"

            # Debian-specific: install parted if needed
            if os_is_debian; then
                source "${SCRIPT_DIR}/../debian/setup-ext4.sh" 2>/dev/null || true
                debian_setup_ext4 "$SYS_USER" "$selected_disk"
            fi

            # Warning & Confirmation
            echo -e "${RED}${BOLD}!!! WARNING !!! WARNING !!! WARNING !!!${NC}"
            echo -e "${RED}This operation will DESTROY all data on ${DISK_BY_ID}.${NC}"
            read -r -p "Type 'yes' to proceed, or anything else to abort: " confirm_wipe

            if [ "$confirm_wipe" != "yes" ]; then
                echo -e "${YELLOW}Operation aborted by user.${NC}"
                read -r -p "Press Enter to return to main menu..." _
                continue
            fi

            # Create partition
            echo -e "\n--> Creating GPT Partition Table..."
            ext4_create_partition "$DISK_BY_ID"

            echo "--> Waiting for partition creation..."
            sleep 2

            # Find partition name
            PART_NAME=$(ext4_find_partition "$selected_disk")
            if [ -z "$PART_NAME" ]; then
                error "Could not locate the newly created partition device."
                exit 1
            fi

            PART_BY_ID=$(get_disk_by_id "$PART_NAME")
            echo -e "Detected partition: ${GREEN}/dev/${PART_NAME}${NC} -> ${GREEN}${PART_BY_ID}${NC}"

            # Format
            echo -e "\n--> Formatting as ext4..."
            ext4_format "$PART_BY_ID"

            # Mount
            read -r -p "Enter desired mount point path [default: /bulk]: " MOUNT_POINT
            MOUNT_POINT=${MOUNT_POINT:-/bulk}

            if [ ! -d "$MOUNT_POINT" ]; then
                echo "--> Creating mount directory: ${MOUNT_POINT}"
                mkdir -p "$MOUNT_POINT"
            fi

            if mountpoint -q "$MOUNT_POINT"; then
                echo -e "${YELLOW}Warning: ${MOUNT_POINT} is already mounted. Attempting to unmount first...${NC}"
                umount "$MOUNT_POINT" || true
            fi

            echo "--> Mounting partition to ${MOUNT_POINT}..."
            ext4_mount "$PART_BY_ID" "$MOUNT_POINT"

            # fstab
            read -r -p "Configure automatic mounting on boot in /etc/fstab? (y/n) [y]: " configure_fstab
            configure_fstab=${configure_fstab:-y}
            if [[ "$configure_fstab" =~ ^[Yy]$ ]]; then
                ext4_setup_fstab "$PART_BY_ID" "$MOUNT_POINT"
            fi

            # Permissions
            echo -e "--> Setting ownership to ${GREEN}${SYS_USER}${NC}..."
            run chown -R "${SYS_USER}:${SYS_USER}" "$MOUNT_POINT"

            echo -e "\n${GREEN}✔ Ext4 Partition successfully created!${NC}"
            echo -e "  Device:      ${PART_BY_ID}"
            echo -e "  Mount Point: ${MOUNT_POINT}"
            read -r -p "Press Enter to return to main menu..." _
            ;;
        2)
            echo ""
            echo -e "${CYAN}--> Preparing ZFS Storage Pool Setup...${NC}"

            # Debian-specific: install ZFS if needed
            if os_is_debian && ! zfs_check_installed; then
                source "${SCRIPT_DIR}/../debian/install-zfs.sh" 2>/dev/null || true
                debian_install_zfs
            fi

            if ! zfs_check_installed; then
                error "ZFS tools are not available. Install them first."
                read -r -p "Press Enter to return to main menu..." _
                continue
            fi

            if ! zfs_module_loaded; then
                echo "--> Loading ZFS kernel module..."
                modprobe zfs || true
            fi

            echo "Choose ZFS configuration type:"
            echo "  1) Single Disk Pool (No redundancy)"
            echo "  2) Mirrored Pool (Requires 2 disks)"
            echo "  3) Return to Main Menu"
            echo ""
            read -r -p "Select ZFS layout [1-3]: " zfs_choice

            if [ "$zfs_choice" = "1" ]; then
                read -r -p "Select a disk by ID [1-${num_disks}]: " disk_id
                if ! [[ "$disk_id" =~ ^[0-9]+$ ]] || [ "$disk_id" -lt 1 ] || [ "$disk_id" -gt "$num_disks" ]; then
                    echo -e "${RED}Invalid selection.${NC}"
                    read -r -p "Press Enter to return to main menu..." _
                    continue
                fi
                selected_entry="${suitable_disks[$((disk_id - 1))]}"
                IFS=';' read -r selected_disk _ <<< "$selected_entry"

            elif [ "$zfs_choice" = "2" ]; then
                if [ "$num_disks" -lt 2 ]; then
                    echo -e "${RED}Error: A mirrored pool requires at least 2 available disks.${NC}"
                    read -r -p "Press Enter to return to main menu..." _
                    continue
                fi

                read -r -p "Select the FIRST disk by ID [1-${num_disks}]: " disk1_id
                read -r -p "Select the SECOND disk by ID [1-${num_disks}]: " disk2_id

                if [ "$disk1_id" = "$disk2_id" ]; then
                    echo -e "${RED}Error: You must select two distinct disks.${NC}"
                    read -r -p "Press Enter to return to main menu..." _
                    continue
                fi

                if ! [[ "$disk1_id" =~ ^[0-9]+$ ]] || [ "$disk1_id" -lt 1 ] || [ "$disk1_id" -gt "$num_disks" ] || \
                   ! [[ "$disk2_id" =~ ^[0-9]+$ ]] || [ "$disk2_id" -lt 1 ] || [ "$disk2_id" -gt "$num_disks" ]; then
                    echo -e "${RED}Invalid selection.${NC}"
                    read -r -p "Press Enter to return to main menu..." _
                    continue
                fi

                disk1_entry="${suitable_disks[$((disk1_id - 1))]}"
                disk2_entry="${suitable_disks[$((disk2_id - 1))]}"
                IFS=';' read -r disk1 _ <<< "$disk1_entry"
                IFS=';' read -r disk2 _ <<< "$disk2_entry"
            else
                continue
            fi

            # Gather pool parameters
            echo ""
            read -r -p "Enter name for the new ZFS pool [default: vault]: " POOL_NAME
            POOL_NAME=${POOL_NAME:-vault}

            if zpool list "$POOL_NAME" &>/dev/null; then
                error "A ZFS pool named '${POOL_NAME}' already exists."
                read -r -p "Press Enter to return to main menu..." _
                continue
            fi

            read -r -p "Create an encrypted dataset inside '${POOL_NAME}'? (y/n) [y]: " create_encrypted
            create_encrypted=${create_encrypted:-y}

            DATASET_NAME=""
            if [[ "$create_encrypted" =~ ^[Yy]$ ]]; then
                read -r -p "Enter dataset name [default: secure]: " DATASET_NAME
                DATASET_NAME=${DATASET_NAME:-secure}
            fi

            # Calculate ARC limit
            ARC_RECOMMENDED=$(zfs_calculate_arc)
            read -r -p "Configure ZFS RAM limit (ARC cache)? (y/n) [y]: " limit_arc
            limit_arc=${limit_arc:-y}

            ARC_LIMIT_INPUT=""
            if [[ "$limit_arc" =~ ^[Yy]$ ]]; then
                local total_ram_gb=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
                echo -e "Total System Memory: ${CYAN}${total_ram_gb} GB${NC}"
                read -r -p "Enter ARC RAM Limit (e.g., 3G, 4G, 512M) [default: ${ARC_RECOMMENDED}]: " ARC_LIMIT_INPUT
                ARC_LIMIT_INPUT=${ARC_LIMIT_INPUT:-$ARC_RECOMMENDED}
            fi

            # Confirmation
            echo -e "\n${RED}${BOLD}!!! WARNING !!! WARNING !!! WARNING !!!${NC}"
            echo -e "${RED}This will DESTROY all data on the selected disk(s).${NC}"
            echo ""
            echo -e "${BOLD}Setup Summary:${NC}"
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
                echo -e "${YELLOW}Operation aborted.${NC}"
                read -r -p "Press Enter to return to main menu..." _
                continue
            fi

            # Execute
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

            # Encrypted dataset
            if [[ "$create_encrypted" =~ ^[Yy]$ ]]; then
                echo -e "\n--> Creating Encrypted Dataset..."
                echo -e "${YELLOW}Enter a secure passphrase when prompted.${NC}"
                zfs_create_encrypted_dataset "$POOL_NAME" "$DATASET_NAME"
                echo -e "${GREEN}✔ Encrypted dataset created.${NC}"
            fi

            # ARC limit
            if [[ "$limit_arc" =~ ^[Yy]$ ]] && [ -n "$ARC_LIMIT_INPUT" ]; then
                ARC_BYTES=$(parse_to_bytes "$ARC_LIMIT_INPUT")
                if [ "$ARC_BYTES" -gt 0 ]; then
                    echo -e "\n--> Limiting ARC to ${ARC_LIMIT_INPUT}..."
                    zfs_configure_arc "$ARC_BYTES"
                    echo -e "${GREEN}✔ ARC limit configured.${NC}"
                fi
            fi

            # Permissions
            echo -e "\n--> Aligning permissions to ${GREEN}${SYS_USER}${NC}..."
            run chown -R "${SYS_USER}:${SYS_USER}" "/${POOL_NAME}"
            if [[ "$create_encrypted" =~ ^[Yy]$ ]]; then
                run chown -R "${SYS_USER}:${SYS_USER}" "/${POOL_NAME}/${DATASET_NAME}"
            fi

            echo -e "\n${GREEN}✔ ZFS Pool provisioned successfully!${NC}"
            echo -e "  Pool Name:  ${POOL_NAME}"
            echo -e "  Mount Point: /${POOL_NAME}"
            read -r -p "Press Enter to return to main menu..." _
            ;;
        3)
            continue
            ;;
        4)
            echo "Exiting wizard."
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please choose 1-4.${NC}"
            sleep 2
            ;;
    esac
done
