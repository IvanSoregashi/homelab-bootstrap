#!/bin/bash

parse_to_bytes() {
    local input="$1"
    input=$(echo "$input" | xargs | tr '[:lower:]' '[:upper:]')
    if [[ "$input" =~ ^[0-9]+G$ ]]; then
        local num="${input%G}"
        echo "$((num * 1024 * 1024 * 1024))"
    elif [[ "$input" =~ ^[0-9]+M$ ]]; then
        local num="${input%M}"
        echo "$((num * 1024 * 1024))"
    elif [[ "$input" =~ ^[0-9]+K$ ]]; then
        local num="${input%K}"
        echo "$((num * 1024))"
    elif [[ "$input" =~ ^[0-9]+$ ]]; then
        echo "$input"
    else
        echo "0"
    fi
}

zfs_calculate_arc() {
    if [ ! -f /proc/meminfo ]; then
        echo "1G"
        return
    fi
    local total_ram_kb
    total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local suggest_bytes=$((total_ram_kb * 1024 / 4))
    local suggest_gb=$((suggest_bytes / 1024 / 1024 / 1024))
    if [ "$suggest_gb" -gt 0 ]; then
        echo "${suggest_gb}G"
    else
        echo "512M"
    fi
}

zfs_create_pool() {
    local pool_name="$1"
    local pool_type="$2"
    shift 2
    local disks=("$@")

    local zpool_args=(
        create -f -o ashift=12
        -O acltype=posixacl
        -O xattr=sa
        -O dnodesize=auto
        -O normalization=formD
        -O devices=off
        "$pool_name"
    )

    if [ "$pool_type" = "mirror" ]; then
        zpool_args+=(mirror)
    fi

    for disk in "${disks[@]}"; do
        zpool_args+=("$disk")
    done

    run zpool "${zpool_args[@]}"
}

zfs_create_encrypted_dataset() {
    local pool_name="$1"
    local dataset_name="$2"

    run zfs create \
        -o encryption=on \
        -o keyformat=passphrase \
        -o keylocation=prompt \
        "${pool_name}/${dataset_name}"
}

zfs_configure_arc() {
    local arc_bytes="$1"
    run mkdir -p /etc/modprobe.d
    echo "options zfs zfs_arc_max=${arc_bytes}" | run tee /etc/modprobe.d/zfs.conf > /dev/null
    run update-initramfs -u -k all
}

zfs_check_installed() {
    command -v zfs &>/dev/null && command -v zpool &>/dev/null
}

zfs_module_loaded() {
    lsmod | grep -q zfs 2>/dev/null
}
