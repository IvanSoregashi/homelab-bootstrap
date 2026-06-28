#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

debian_install_zram() {
    if dpkg -s zram-tools 2>/dev/null | grep -q "Status: install ok installed"; then
        echo "  zram-tools already installed. Skipping."
        return 0
    fi
    echo "  Installing zram-tools..."
    apt-get update && apt-get install -y zram-tools
}

debian_setup_zram() {
    if systemctl is-enabled --quiet zramswap 2>/dev/null && systemctl is-active --quiet zramswap 2>/dev/null; then
        echo "  ZRAM already configured and active. Skipping."
        return 0
    fi

    echo "  Configuring ZRAM..."
    cat << EOF > /etc/default/zramswap
ALGO=zstd
SIZE=3072
PRIORITY=100
EOF

    systemctl enable --now zramswap 2>/dev/null || true
    systemctl restart zramswap 2>/dev/null || true
}

debian_setup_swapfile() {
    local data_path="$1"
    local swap_file="${data_path}/swapfile"

    if [ -f "$swap_file" ]; then
        echo "  Swap file already exists at ${swap_file}. Skipping creation."
    else
        echo "  Creating 4GB swap file on data volume..."
        fallocate -l 4G "$swap_file"
        chmod 600 "$swap_file"
        mkswap "$swap_file"
    fi

    if ! grep -q "$swap_file" /etc/fstab 2>/dev/null; then
        echo "  Adding swap to fstab..."
        echo "${swap_file}   none   swap   defaults,pri=1   0   0" >> /etc/fstab
    fi

    swapon -a
}

debian_tune_swappiness() {
    if [ "$(sysctl -n vm.swappiness 2>/dev/null)" = "10" ]; then
        echo "  vm.swappiness already set to 10. Skipping."
        return 0
    fi

    echo "  Setting vm.swappiness to 10..."
    sysctl -w vm.swappiness=10
    if ! grep -q "vm.swappiness" /etc/sysctl.d/99-sysctl.conf 2>/dev/null; then
        echo "vm.swappiness=10" >> /etc/sysctl.d/99-sysctl.conf
    else
        sed -i 's/^vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.d/99-sysctl.conf
    fi
    sysctl -p /etc/sysctl.d/99-sysctl.conf
}
