#!/bin/bash

ext4_find_partition() {
    local disk_name="$1"
    if [ -b "/dev/${disk_name}p1" ]; then
        echo "${disk_name}p1"
    elif [ -b "/dev/${disk_name}1" ]; then
        echo "${disk_name}1"
    else
        for p in "/dev/${disk_name}"*; do
            if [ -b "$p" ] && [ "$p" != "/dev/${disk_name}" ]; then
                basename "$p"
                return 0
            fi
        done
        echo ""
    fi
}

ext4_create_partition() {
    local disk_by_id="$1"

    run parted "$disk_by_id" mklabel gpt
    run parted "$disk_by_id" mkpart primary ext4 0% 100%
}

ext4_format() {
    local part_by_id="$1"
    run mkfs.ext4 "$part_by_id"
}

ext4_mount() {
    local part_by_id="$1"
    local mount_point="$2"
    run mount "$part_by_id" "$mount_point"
}

ext4_setup_fstab() {
    local part_by_id="$1"
    local mount_point="$2"
    if grep -qF "$mount_point" /etc/fstab 2>/dev/null; then
        warn "An entry for $mount_point already exists in /etc/fstab. Skipping."
        return
    fi
    echo "${part_by_id} ${mount_point} ext4 defaults 0 2" | run tee -a /etc/fstab > /dev/null
}
