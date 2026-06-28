#!/bin/bash

debian_optimize_memory() {
    local data_path="$1"
    local swap_file="${data_path}/swapfile"

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/../../lib/common.sh"

    echo -e "--> Setting up Memory/Swap Optimizations..."

    echo "  Installing and configuring ZRAM..."
    apt-get update && apt-get install -y zram-tools

    cat << EOF > /etc/default/zramswap
ALGO=zstd
SIZE=3072
PRIORITY=100
EOF

    systemctl enable --now zramswap
    systemctl restart zramswap

    if [ ! -f "$swap_file" ]; then
        echo "  Creating 4GB NVMe fallback swap file..."
        fallocate -l 4G "$swap_file"
        chmod 600 "$swap_file"
        mkswap "$swap_file"
    fi

    if ! grep -q "$swap_file" /etc/fstab; then
        echo "  Adding swap to fstab..."
        echo "${swap_file}   none   swap   defaults,pri=1   0   0" >> /etc/fstab
    fi

    swapon -a

    echo "  Setting vm.swappiness to 10..."
    sysctl -w vm.swappiness=10
    if ! grep -q "vm.swappiness" /etc/sysctl.d/99-sysctl.conf 2>/dev/null; then
        echo "vm.swappiness=10" >> /etc/sysctl.d/99-sysctl.conf
    else
        sed -i 's/^vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.d/99-sysctl.conf
    fi
    sysctl -p /etc/sysctl.d/99-sysctl.conf

    echo -e "  Memory optimization complete."
}
