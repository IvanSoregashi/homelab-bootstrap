#!/bin/bash

debian_install_zfs() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/../lib/common.sh"

    echo -e "--> Checking ZFS installation requirements..."

    # Enable contrib and non-free on Debian if needed
    if ! apt-cache show zfsutils-linux &>/dev/null; then
        echo -e "${YELLOW}Warning: 'zfsutils-linux' is not visible in current package sources.${NC}"
        read -r -p "Automatically enable 'contrib' and 'non-free' sources? (y/n) [y]: " enable_repo
        enable_repo=${enable_repo:-y}
        if [[ ! "$enable_repo" =~ ^[Yy]$ ]]; then
            error "Cannot proceed without enabling ZFS packages."
            exit 1
        fi

        # Modern DEB822 format (Debian 12+)
        if [ -f "/etc/apt/sources.list.d/debian.sources" ]; then
            sed -i -E 's/^(Components:.*main)(.*)/\1 contrib non-free non-free-firmware\2/' /etc/apt/sources.list.d/debian.sources
            sed -i -E 's/contrib contrib/contrib/g; s/non-free non-free/non-free/g; s/non-free-firmware non-free-firmware/non-free-firmware/g' /etc/apt/sources.list.d/debian.sources
        fi

        # Legacy format
        if [ -f "/etc/apt/sources.list" ]; then
            sed -i -E '/^deb/ s/ main/ main contrib non-free non-free-firmware/g' /etc/apt/sources.list
            sed -i -E 's/contrib contrib/contrib/g; s/non-free non-free/non-free/g; s/non-free-firmware non-free-firmware/non-free-firmware/g' /etc/apt/sources.list
        fi

        apt-get update

        if ! apt-cache show zfsutils-linux &>/dev/null; then
            error "ZFS packages still not visible. Check internet connection."
            exit 1
        fi
        echo -e "${GREEN}✔ Repository components enabled.${NC}"
    fi

    echo -e "${YELLOW}Note: Compiling ZFS kernel modules via DKMS may take several minutes.${NC}"
    read -r -p "Install ZFS utilities now? (y/n) [y]: " inst_zfs
    inst_zfs=${inst_zfs:-y}
    if [[ ! "$inst_zfs" =~ ^[Yy]$ ]]; then
        error "ZFS setup aborted."
        exit 1
    fi

    echo "--> Installing ZFS packages..."
    apt-get install -y linux-headers-amd64 zfs-dkms zfsutils-linux

    echo "--> Loading ZFS kernel module..."
    modprobe zfs || { error "Error loading ZFS module. Reboot may be required."; exit 1; }
    echo -e "${GREEN}✔ ZFS installed and loaded.${NC}"
}
