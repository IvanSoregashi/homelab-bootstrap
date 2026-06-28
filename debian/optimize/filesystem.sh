#!/bin/bash

debian_optimize_filesystem() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/../../lib/common.sh"

    echo -e "--> Optimizing Filesystem for eMMC/SSD longevity..."

    echo "  Setting noatime on root filesystem..."
    cp /etc/fstab /etc/fstab.bak 2>/dev/null || true

    sed -i 's/\(UUID=[^ ]* \/ [^ ]* \)\([^ ]*\)\(.*\)/\1\2,noatime\3/' /etc/fstab

    mount -o remount /
    systemctl daemon-reload

    echo -e "  Filesystem optimization complete."
}
