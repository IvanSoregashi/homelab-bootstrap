#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

debian_disable_atime() {
    if mount | grep " / " | grep -q "noatime"; then
        echo "  Root filesystem already has noatime. Skipping."
        return 0
    fi

    echo -e "--> Optimizing Filesystem for eMMC/SSD longevity..."

    echo "  Setting noatime on root filesystem..."
    cp /etc/fstab /etc/fstab.bak 2>/dev/null || true

    sed -i 's/\(UUID=[^ ]* \/ [^ ]* \)\([^ ]*\)\(.*\)/\1\2,noatime\3/' /etc/fstab

    mount -o remount /
    systemctl daemon-reload

    echo -e "  Filesystem optimization complete."
}
