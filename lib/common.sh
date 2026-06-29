#!/bin/bash

[ -n "${_COMMON_SH_SOURCED:-}" ] && return
readonly _COMMON_SH_SOURCED=1

# Color constants
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Logging helpers
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
header()  { echo -e "${CYAN}======================================================================${NC}"; echo -e "${BOLD}  $*${NC}"; echo -e "${CYAN}======================================================================${NC}"; }
subheader() { echo -e "${BLUE}----------------------------------------------------------------------${NC}"; }

run() {
    echo -e "  ${BLUE}→${NC} $*"
    "$@"
}

detect_user() {
    echo "${SUDO_USER:-$(id -un 1000 2>/dev/null || echo "$USER")}"
}

require_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run with root privileges (sudo)."
        exit 1
    fi
}

# Resolve a device name to its /dev/disk/by-id persistent path
get_disk_by_id() {
    local dev_name="$1"
    local real_dev
    real_dev=$(readlink -f "/dev/${dev_name}")

    local candidate=""
    for link in /dev/disk/by-id/*; do
        if [ -L "$link" ] && [ "$(readlink -f "$link")" = "$real_dev" ]; then
            local base_link
            base_link=$(basename "$link")
            if [[ "$dev_name" =~ [0-9]+$ ]]; then
                if [[ "$base_link" == *"-part"* ]]; then
                    echo "$link"
                    return 0
                fi
            else
                if [[ "$base_link" != *"-part"* ]] && [[ "$base_link" != nvme-eui.* ]] && [[ "$base_link" != wwn-* ]]; then
                    echo "$link"
                    return 0
                fi
            fi
            candidate="$link"
        fi
    done

    if [ -n "$candidate" ]; then
        echo "$candidate"
    else
        echo "/dev/${dev_name}"
    fi
}

# Check if a mount path is safe to write to
check_mount_safety() {
    local target_path="$1"
    local path_type="$2"

    if mountpoint -q "$target_path" || (command -v zfs &>/dev/null && zfs mount 2>/dev/null | grep -F -q "$target_path"); then
        echo "  $path_type path ($target_path) is actively mounted. ${GREEN}Safe.${NC}"
        return 0
    fi

    if grep -F -q "$target_path" /etc/fstab 2>/dev/null; then
        error "$path_type path ($target_path) is defined in /etc/fstab but is NOT mounted!"
        echo "  Running would write files directly to your system drive."
        exit 1
    fi

    if command -v zfs &>/dev/null && zfs list -H -o mountpoint 2>/dev/null | grep -x -q "$target_path"; then
        error "$path_type path ($target_path) is an unmounted ZFS dataset!"
        echo "  Please unlock and mount your ZFS pool first."
        exit 1
    fi

    if [ -w "$target_path" ]; then
        echo "  $path_type path ($target_path) is a standard writeable directory. ${GREEN}Safe.${NC}"
        return 0
    else
        error "$path_type path ($target_path) is not writeable."
        exit 1
    fi
}

# Add an fstab bind mount entry if not already present
add_fstab_bind() {
    local src="$1"
    local dst="$2"
    if ! grep -qs "$dst" /etc/fstab 2>/dev/null; then
        echo "  Appending fstab bind mount: $src → $dst"
        echo "$src    $dst    none    bind,nofail    0    0" | tee -a /etc/fstab > /dev/null
    else
        echo "  fstab entry for $dst already exists. Skipping."
    fi
}

analyze_disk_suitability() {
    local disk_name="$1"
    local dev_path="/dev/${disk_name}"
    local -n reasons_arr=$2

    local active_mounts
    active_mounts=$(lsblk -no MOUNTPOINT "$dev_path" 2>/dev/null | grep -v '^$' || true)
    if [ -n "$active_mounts" ]; then
        local formatted_mounts
        formatted_mounts=$(echo "$active_mounts" | paste -sd, -)
        reasons_arr+=("Device or child partition is actively mounted at: ${formatted_mounts}")
    fi

    local mps
    mps=$(lsblk -rno MOUNTPOINT "$dev_path" 2>/dev/null | grep -v '^$' || true)
    for mp in $mps; do
        if [ "$mp" = "/" ]; then
            reasons_arr+=("Contains the active root filesystem (/)")
        elif [ "$mp" = "/boot" ]; then
            reasons_arr+=("Contains the active system boot directory (/boot)")
        elif [[ "$mp" == /boot/* ]]; then
            reasons_arr+=("Contains system bootloader partition (${mp})")
        fi
    done

    local fstypes
    fstypes=$(lsblk -no FSTYPE "$dev_path" 2>/dev/null | grep -v '^$' || true)
    if echo "$fstypes" | grep -q 'zfs_member'; then
        reasons_arr+=("ZFS member signature detected (belongs to a pool)")
    fi
    if command -v zpool &>/dev/null; then
        if zpool status -v 2>/dev/null | grep -q "$disk_name"; then
            reasons_arr+=("Device is claimed by an active ZFS pool")
        fi
    fi

    if echo "$fstypes" | grep -q 'swap'; then
        reasons_arr+=("Contains virtual memory swap space")
    fi

    if [ -f "/sys/block/${disk_name}/ro" ] && [ "$(cat "/sys/block/${disk_name}/ro")" = "1" ]; then
        reasons_arr+=("Device is write-protected / read-only")
    fi

    if [[ "$disk_name" =~ ^loop ]]; then reasons_arr+=("Virtual loopback device"); fi
    if [[ "$disk_name" =~ ^ram ]]; then reasons_arr+=("System RAM disk"); fi
    if [[ "$disk_name" =~ ^dm- ]]; then reasons_arr+=("Device Mapper block volume (LVM, LUKS, or mdadm)"); fi
    if [[ "$disk_name" =~ ^md ]]; then reasons_arr+=("Software RAID (mdadm) volume"); fi
    if [[ "$disk_name" =~ boot[0-9]$ ]]; then reasons_arr+=("Hardware bootloader partition (mmcblk boot layer)"); fi
}

scan_storage() {
    local -n suitable_ref=$1
    suitable_ref=()

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

        if [ ${#reasons[@]} -eq 0 ]; then
            suitable_ref+=("${dev_name};${size};${model}")
        fi
    done
}
