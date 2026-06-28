#!/bin/bash

debian_setup_ext4() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/../lib/common.sh"

    local sys_user="$1"
    local disk_name="$2"

    if ! command -v parted &>/dev/null; then
        echo -e "${YELLOW}'parted' utility is required but not installed.${NC}"
        read -r -p "Install parted now? (y/n) [y]: " inst_parted
        inst_parted=${inst_parted:-y}
        if [[ "$inst_parted" =~ ^[Yy]$ ]]; then
            echo "--> Installing parted..."
            apt-get update
            apt-get install -y parted
        else
            error "parted is required to set up partitions."
            exit 1
        fi
    fi
}
